abstract type AbstractHistogram{T} end

#### MEMORY ####

function init(H::Type{<:AbstractHistogram{T}}, lowest_discernible_value, highest_trackable_value, significant_figures) where {T}
    if lowest_discernible_value < 1 || significant_figures < 1 || 5 < significant_figures || lowest_discernible_value * 2 > highest_trackable_value
        error("Invalid significant_figures")
    end

    largest_value_with_single_unit_resolution = 2 * 10^significant_figures
    sub_bucket_count_magnitude = ceil(Int64, log2(largest_value_with_single_unit_resolution))
    sub_bucket_half_count_magnitude = (sub_bucket_count_magnitude > 1 ? sub_bucket_count_magnitude : 1) - 1

    unit_magnitude = floor(UInt64, log2(lowest_discernible_value))

    sub_bucket_count = 2^(sub_bucket_half_count_magnitude + 1)
    sub_bucket_half_count = sub_bucket_count >> 1
    sub_bucket_mask = (sub_bucket_count - 1) << unit_magnitude

    if unit_magnitude + sub_bucket_half_count_magnitude > 61
        error("")
    end

    bucket_count = buckets_needed_to_cover_value(highest_trackable_value, sub_bucket_count, unit_magnitude)
    counts_len = (bucket_count + 1) * (sub_bucket_count ÷ 2)

    return H(lowest_discernible_value, highest_trackable_value, unit_magnitude,
        significant_figures, sub_bucket_half_count_magnitude,
        sub_bucket_half_count, sub_bucket_mask, sub_bucket_count,
        bucket_count, typemax(T), 0, 0, 1.0, 0, zeros(T, counts_len))
end

total_count(h::AbstractHistogram) = h.total_count
total_count!(h::AbstractHistogram, value) = h.total_count = value
min_value(h::AbstractHistogram) = h.min_value
min_value!(h::AbstractHistogram, value) = h.min_value = value
max_value(h::AbstractHistogram) = h.max_value
max_value!(h::AbstractHistogram, value) = h.max_value = value

function hdr_reset(h::AbstractHistogram{T}) where {T}
    total_count!(h, 0)
    min_value!(h, typemax(T))
    max_value!(h, 0)
    fill!(h.counts, 0)
end

### COUNTS ###

@inline function normalize_index(h::AbstractHistogram, index)
    if h.normalizing_index_offset == 0
        return index
    end

    normalized_index = index - h.normalizing_index_offset

    if normalized_index < 0
        adjustment = length(h.counts)
    elseif normalized_index >= length(h.counts)
        adjustment = -length(h.counts)
    end

    return normalized_index + adjustment
end

@inline function counts_get_direct(h::AbstractHistogram, index)
    return @inbounds h.counts[index+1]
end

@inline function counts_get_normalised(h::AbstractHistogram, index)
    return counts_get_direct(h, normalize_index(h, index))
end

@inline function counts_inc_normalised!(h::AbstractHistogram, index, value)
    normalised_index = normalize_index(h, index)
    @inbounds h.counts[normalised_index+1] += value
    h.total_count += value
end

@inline function update_min_max!(h::AbstractHistogram, value)
    h.min_value = min(h.min_value, value)
    h.max_value = max(h.max_value, value)
end

#### UTILITIES ####

function get_bucket_index(h::AbstractHistogram, value)
    pow2ceiling = 64 - leading_zeros(value | h.sub_bucket_mask) # smallest power of 2 containing value
    return pow2ceiling - h.unit_magnitude - (h.sub_bucket_half_count_magnitude + 1)
end

function get_sub_bucket_index(value, bucket_index, unit_magnitude)
    return value >> (bucket_index + unit_magnitude)
end

function counts_index(h::AbstractHistogram, bucket_index, sub_bucket_index)
    bucket_base_index = (bucket_index + 1) << h.sub_bucket_half_count_magnitude # Calculate the index for the first entry in the bucket
    offset_in_bucket = sub_bucket_index - h.sub_bucket_half_count # Calculate the offset in the bucket
    return bucket_base_index + offset_in_bucket
end

function value_from_index(bucket_index, sub_bucket_index, unit_magnitude)
    return Int64(sub_bucket_index) << (bucket_index + unit_magnitude)
end

function counts_index_for(h::AbstractHistogram, value)
    bucket_index = get_bucket_index(h, value)
    sub_bucket_index = get_sub_bucket_index(value, bucket_index, h.unit_magnitude)
    return counts_index(h, bucket_index, sub_bucket_index)
end

function hdr_value_at_index(h::AbstractHistogram, index::Integer)
    bucket_index = (index >> h.sub_bucket_half_count_magnitude) - 1
    sub_bucket_index = (index & (h.sub_bucket_half_count - 1)) + h.sub_bucket_half_count

    if bucket_index < 0
        sub_bucket_index -= h.sub_bucket_half_count
        bucket_index = 0
    end

    return value_from_index(bucket_index, sub_bucket_index, h.unit_magnitude)
end

function hdr_size_of_equivalent_value_range(h::AbstractHistogram{T}, value::T) where {T}
    bucket_index = get_bucket_index(h, value)
    sub_bucket_index = get_sub_bucket_index(value, bucket_index, h.unit_magnitude)
    adjusted_bucket = (sub_bucket_index >= h.sub_bucket_count) ? (bucket_index + 1) : bucket_index
    return 1 << (h.unit_magnitude + adjusted_bucket)
end

function size_of_equivalent_value_range_given_bucket_indices(h::AbstractHistogram, bucket_index, sub_bucket_index)
    adjusted_bucket = (sub_bucket_index >= h.sub_bucket_count) ? (bucket_index + 1) : bucket_index
    return 1 << (h.unit_magnitude + adjusted_bucket)
end

function lowest_equivalent_value(h::AbstractHistogram, value)
    bucket_index = get_bucket_index(h, value)
    sub_bucket_index = get_sub_bucket_index(value, bucket_index, h.unit_magnitude)
    return value_from_index(bucket_index, sub_bucket_index, h.unit_magnitude)
end

function lowest_equivalent_value_given_bucket_indices(h::AbstractHistogram, bucket_index, sub_bucket_index)
    return value_from_index(bucket_index, sub_bucket_index, h.unit_magnitude)
end

function hdr_next_non_equivalent_value(h::AbstractHistogram{T}, value::T) where {T}
    return lowest_equivalent_value(h, value) + hdr_size_of_equivalent_value_range(h, value)
end

function highest_equivalent_value(h::AbstractHistogram, value)
    return hdr_next_non_equivalent_value(h, value) - 1
end

function hdr_median_equivalent_value(h::AbstractHistogram{T}, value::T) where {T}
    return lowest_equivalent_value(h, value) + (hdr_size_of_equivalent_value_range(h, value) >> 1)
end

function non_zero_min(h::AbstractHistogram{T}) where {T}
    if min_value(h) == typemax(T)
        return typemax(T)
    end
    return lowest_equivalent_value(h, min_value(h))
end

function hdr_reset_internal_counters(h::AbstractHistogram{T}) where {T}
    min_non_zero_index = -1
    max_index = -1
    observed_total_count = 0

    for i in eachindex(h.counts)
        if (count = counts_get_direct(h, i)) > 0
            observed_total_count += count
            max_index = i
            if min_non_zero_index == -1 && i != 1
                min_non_zero_index = i
            end
        end
    end

    if max_index == -1
        max_value!(h, 0)
    else
        max_value = hdr_value_at_index(h, max_index)
        max_value!(h, highest_equivalent_value(h, max_value))
    end

    if min_non_zero_index == -1
        min_value!(h, typemax(T))
    else
        min_value!(h, hdr_value_at_index(h, min_non_zero_index))
    end

    total_count!(h, observed_total_count)
end

function buckets_needed_to_cover_value(value::T, sub_bucket_count, unit_magnitude) where {T}
    smallest_untrackable_value = Int64(sub_bucket_count) << unit_magnitude
    buckets_needed = 1
    while smallest_untrackable_value <= value
        if smallest_untrackable_value > typemax(T) ÷ 2
            return buckets_needed + 1
        end
        smallest_untrackable_value <<= 1
        buckets_needed += 1
    end
    return buckets_needed
end

#### UPDATES ####

function hdr_record_value(h::AbstractHistogram{T}, value::T) where {T}
    return hdr_record_values(h, value, 1)
end

@inline function hdr_record_values(h::AbstractHistogram{T}, value::T, count) where {T}
    counts_index = counts_index_for(h, value)

    if value < zero(T) || counts_index < 0 || length(h.counts) <= counts_index
        return false
    end

    counts_inc_normalised!(h, counts_index, count)
    update_min_max!(h, value)

    return true
end

function hdr_record_corrected_value(h::AbstractHistogram{T}, value::T, expected_interval::Int64) where {T}
    return hdr_record_corrected_values(h, value, 1, expected_interval)
end

function hdr_record_corrected_values(h::AbstractHistogram{T}, value::T, count::Int64, expected_interval::Int64) where {T}
    if !hdr_record_values(h, value, count)
        return false
    end

    if expected_interval <= 0 || value <= expected_interval
        return true
    end

    missing_value = value - expected_interval
    while missing_value >= expected_interval
        if !hdr_record_values(h, missing_value, count)
            return false
        end
        missing_value -= expected_interval
    end

    return true
end

function hdr_add(h::AbstractHistogram, from::AbstractHistogram)
    iter = hdr_iter_recorded_init(from)
    dropped = 0

    while hdr_iter_next(iter)
        value = value(iter)
        count = count(iter)

        if !hdr_record_values(h, value, count)
            dropped += count
        end
    end

    return dropped
end

function hdr_add_while_correcting_for_coordinated_omission(h::AbstractHistogram, from::AbstractHistogram, expected_interval::Int64)
    iter = hdr_iter_recorded_init(from)
    dropped = 0

    while hdr_iter_next(iter)
        value = value(iter)
        count = count(iter)

        if !hdr_record_corrected_values(h, value, count, expected_interval)
            dropped += count
        end
    end

    return dropped
end

#### VALUES ####

function hdr_max(h::AbstractHistogram{T}) where {T}
    if max_value(h) == zero(T)
        return 0
    end
    return highest_equivalent_value(h, max_value(h))
end

function hdr_min(h::AbstractHistogram{T}) where {T}
    if hdr_count_at_index(h, 0) > zero(T)
        return 0
    end
    return non_zero_min(h)
end

# FIXME The index assumes 0-based indexing
function get_value_from_idx_up_to_count(h::AbstractHistogram, count_at_percentile)
    count_to_idx = 0
    count_at_percentile = count_at_percentile > 0 ? count_at_percentile : 1
    for idx in 1:length(h.counts)
        count_to_idx += counts_get_direct(h, idx)
        if count_to_idx >= count_at_percentile
            return hdr_value_at_index(h, idx)
        end
    end
    return 0
end

function hdr_value_at_percentile(h::AbstractHistogram, percentile::Float64)
    requested_percentile = percentile < 100.0 ? percentile : 100.0
    count_at_percentile = round(Int64, (requested_percentile / 100) * total_count(h))
    value_from_idx = get_value_from_idx_up_to_count(h, count_at_percentile)
    if percentile == 0.0
        return lowest_equivalent_value(h, value_from_idx)
    end
    return highest_equivalent_value(h, value_from_idx)
end

function hdr_value_at_percentiles(h::AbstractHistogram, percentiles::Vector{Float64}, values::Vector{Int64})
    total_count = total_count(h)
    for i in 1:length(percentiles)
        requested_percentile = percentiles[i] < 100.0 ? percentiles[i] : 100.0
        count_at_percentile = round(Int64, (requested_percentile / 100) * total_count)
        values[i] = count_at_percentile > 1 ? count_at_percentile : 1
    end
    iter = hdr_iter_init(h)
    total = 0
    at_pos = 1
    while hdr_iter_next(iter) && at_pos <= length(percentiles)
        total += iter.count
        while at_pos <= length(percentiles) && total >= values[at_pos]
            values[at_pos] = highest_equivalent_value(h, iter.value)
            at_pos += 1
        end
    end
    return 0
end

function hdr_mean(h::AbstractHistogram{T}) where {T}
    total = 0
    count = 0
    total_count = total_count(h)
    if total_count == zero(T)
        return 0.0
    end
    iter = hdr_iter_init(h)
    while hdr_iter_next(iter) && count < total_count
        if iter.count != 0
            count += iter.count
            total += iter.count * hdr_median_equivalent_value(h, iter.value)
        end
    end
    return total / total_count
end

function hdr_stddev(h::AbstractHistogram{T}) where {T}
    total_count = total_count(h)
    if total_count == zero(T)
        return 0.0
    end
    mean = hdr_mean(h)
    geometric_dev_total = 0.0
    iter = hdr_iter_init(h)
    while hdr_iter_next(iter)
        if iter.count != 0
            dev = hdr_median_equivalent_value(h, iter.value) - mean
            geometric_dev_total += dev^2 * iter.count
        end
    end
    return sqrt(geometric_dev_total / total_count)
end

function hdr_values_are_equivalent(h::AbstractHistogram, a::Int64, b::Int64)
    return lowest_equivalent_value(h, a) == lowest_equivalent_value(h, b)
end

function hdr_lowest_equivalent_value(h::AbstractHistogram, value::Int64)
    return lowest_equivalent_value(h, value)
end

function hdr_count_at_value(h::AbstractHistogram, value::Int64)
    return counts_get_normalised(h, counts_index_for(h, value))
end

function hdr_count_at_index(h::AbstractHistogram, index::Int32)
    return counts_get_normalised(h, index)
end

#### ITERATORS ####

# abstract type AbstractHdrIterator end

# mutable struct Iterator <: AbstractHdrIterator
#     h::Histogram
#     counts_index::Int32
#     total_count::Int64
#     count::Int64
#     cumulative_count::Int64
#     value::Int64
#     highest_equivalent_value::Int64
#     lowest_equivalent_value::Int64
#     median_equivalent_value::Int64
#     value_iterated_from::Int64
#     value_iterated_to::Int64
# end

# struct hdr_iter
#     {
#         const struct hdr_histogram* h;
#         /** raw index into the counts array */
#         int32_t counts_index;
#         /** snapshot of the length at the time the iterator is created */
#         int64_t total_count;
#         /** value directly from array for the current counts_index */
#         int64_t count;
#         /** sum of all of the counts up to and including the count at this index */
#         int64_t cumulative_count;
#         /** The current value based on counts_index */
#         int64_t value;
#         int64_t highest_equivalent_value;
#         int64_t lowest_equivalent_value;
#         int64_t median_equivalent_value;
#         int64_t value_iterated_from;
#         int64_t value_iterated_to;

#     };

#     static bool has_buckets(struct hdr_iter* iter)
# {
#     return iter->counts_index < iter->h->counts_len;
# }

# static bool has_next(struct hdr_iter* iter)
# {
#     return iter->cumulative_count < iter->total_count;
# }

# static bool move_next(struct hdr_iter* iter)
# {
#     iter->counts_index++;

#     if (!has_buckets(iter))
#     {
#         return false;
#     }

#     iter->count = counts_get_normalised(iter->h, iter->counts_index);
#     iter->cumulative_count += iter->count;
#     const int64_t value = hdr_value_at_index(iter->h, iter->counts_index);
#     const int32_t bucket_index = get_bucket_index(iter->h, value);
#     const int32_t sub_bucket_index = get_sub_bucket_index(value, bucket_index, iter->h->unit_magnitude);
#     const int64_t leq = lowest_equivalent_value_given_bucket_indices(iter->h, bucket_index, sub_bucket_index);
#     const int64_t size_of_equivalent_value_range = size_of_equivalent_value_range_given_bucket_indices(
#         iter->h, bucket_index, sub_bucket_index);
#     iter->lowest_equivalent_value = leq;
#     iter->value = value;
#     iter->highest_equivalent_value = leq + size_of_equivalent_value_range - 1;
#     iter->median_equivalent_value = leq + (size_of_equivalent_value_range >> 1);

#     return true;
# }

# static int64_t peek_next_value_from_index(struct hdr_iter* iter)
# {
#     return hdr_value_at_index(iter->h, iter->counts_index + 1);
# }

# static bool next_value_greater_than_reporting_level_upper_bound(
#     struct hdr_iter *iter, int64_t reporting_level_upper_bound)
# {
#     if (iter->counts_index >= iter->h->counts_len)
#     {
#         return false;
#     }

#     return peek_next_value_from_index(iter) > reporting_level_upper_bound;
# }

# static bool basic_iter_next(struct hdr_iter *iter)
# {
#     if (!has_next(iter) || iter->counts_index >= iter->h->counts_len)
#     {
#         return false;
#     }

#     move_next(iter);

#     return true;
# }

# static void update_iterated_values(struct hdr_iter* iter, int64_t new_value_iterated_to)
# {
#     iter->value_iterated_from = iter->value_iterated_to;
#     iter->value_iterated_to = new_value_iterated_to;
# }

# void hdr_iter_init(struct hdr_iter* iter, const struct hdr_histogram* h)
# {
#     iter->h = h;

#     iter->counts_index = -1;
#     iter->total_count = h->total_count;
#     iter->count = 0;
#     iter->cumulative_count = 0;
#     iter->value = 0;
#     iter->highest_equivalent_value = 0;
#     iter->value_iterated_from = 0;
#     iter->value_iterated_to = 0;

#     iter->count_added_in_this_iteration_step = 0;
#     iter->value_units_per_bucket = value_units_per_bucket;
#     iter->next_value_reporting_level = value_units_per_bucket;
#     iter->next_value_reporting_level_lowest_equivalent = lowest_equivalent_value(h, value_units_per_bucket);

#     iter->_next_fp = iter_linear_next;
# }

# bool hdr_iter_next(struct hdr_iter* iter)
# {
#     bool result = move_next(iter);

#     if (result)
#     {
#         update_iterated_values(iter, iter->value);
#     }

#     return result;
# }
