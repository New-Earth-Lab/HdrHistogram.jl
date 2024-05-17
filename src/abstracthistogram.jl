abstract type AbstractHistogram{C} end

#### MEMORY ####

function _init(H::Type{<:AbstractHistogram{C}},
    lowest_discernible_value::Integer,
    highest_trackable_value::Integer,
    significant_figures::Integer,
    auto_resize::Bool) where {C}
    if !(0 < significant_figures <= 5)
        throw(ArgumentError("number of significant_figures must be between 0 and 5"))
    end

    if !(1 <= lowest_discernible_value <= (typemax(Int64) / 2))
        throw(ArgumentError("lowest_discernible_value >=1 and <= $(typemax(Int64) / 2)"))
    end

    if !(highest_trackable_value >= lowest_discernible_value * 2)
        throw(ArgumentError("highest_trackable_value must be >= 2 * lowest_discernible_value"))
    end

    largest_value_with_single_unit_resolution = 2 * 10^significant_figures
    sub_bucket_count_magnitude = ceil(Int64, log2(largest_value_with_single_unit_resolution))
    sub_bucket_half_count_magnitude = sub_bucket_count_magnitude - 1

    unit_magnitude = floor(UInt64, log2(lowest_discernible_value)) % 64

    if sub_bucket_count_magnitude + unit_magnitude > 62
        # sub_bucket_count entries can't be represented, with unit_magnitude applied, in a positive Int64.
        # Technically it still sort of works if their sum is 63: you can represent all but the last number
        # in the shifted sub_bucket_count. However, the utility of such a histogram vs ones whose magnitude here
        # fits in 62 bits is debatable, and it makes it harder to work through the logic.
        # Sums larger than 64 are totally broken as leading_zero_count_base would go negative.
        throw(ArgumentError("Cannot represent significant_figures worth of values beyond lowest_discernible_value"))
    end

    # Establish leading_zero_count_base, used in get_bucket_index() fast path:
    # subtract the bits that would be used by the largest value in bucket 0.
    leading_zero_count_base = 64 - unit_magnitude - sub_bucket_count_magnitude

    sub_bucket_count = 2^sub_bucket_count_magnitude
    sub_bucket_half_count = sub_bucket_count >> 1
    sub_bucket_mask = (sub_bucket_count - 1) << unit_magnitude

    bucket_count = _buckets_needed_to_cover_value(C, highest_trackable_value, sub_bucket_count, unit_magnitude)
    counts_len = (bucket_count + 1) * sub_bucket_half_count

    return H(lowest_discernible_value, highest_trackable_value, unit_magnitude,
        significant_figures, sub_bucket_half_count_magnitude,
        sub_bucket_half_count, sub_bucket_mask, sub_bucket_count, leading_zero_count_base,
        bucket_count, typemax(C), 0, 0, 1.0, auto_resize, 0, zeros(C, counts_len))
end

_total_count(h::AbstractHistogram) = h.total_count
_total_count!(h::AbstractHistogram, value) = h.total_count = value
_total_count_inc!(h::AbstractHistogram, value) = h.total_count += value
_min_value(h::AbstractHistogram) = h.min_value
_min_value!(h::AbstractHistogram, value) = h.min_value = value
_max_value(h::AbstractHistogram) = h.max_value
_max_value!(h::AbstractHistogram, value) = h.max_value = value
_auto_resize(h::AbstractHistogram) = h.auto_resize

function reset!(h::AbstractHistogram{C}) where {C}
    _total_count!(h, 0)
    _min_value!(h, typemax(C))
    _max_value!(h, 0)
    fill!(h.counts, 0)
end

### COUNTS ###

function _resize!(h::AbstractHistogram{C}, highest_trackable_value) where {C}
    if !(highest_trackable_value >= h.lowest_discernible_value * 2)
        throw(ArgumentError("highest_trackable_value must be >= 2 * lowest_discernible_value"))
    end
    bucket_count = _buckets_needed_to_cover_value(C, highest_trackable_value, h.sub_bucket_count, h.unit_magnitude)
    counts_len = (bucket_count + 1) * h.sub_bucket_half_count
    old_len = length(h.counts)
    resize!(h.counts, counts_len)
    fill!(view(h.counts, old_len+1:counts_len), 0)
    h.bucket_count = bucket_count
    h.highest_trackable_value = highest_trackable_value
end

@inline function _normalize_index(h::AbstractHistogram, index)
    if h.normalizing_index_offset == 0
        return index
    end

    normalized_index = index - h.normalizing_index_offset

    array_length = length(h.counts)
    if normalized_index < 0
        normalized_index += array_length
    elseif normalized_index >= array_length
        normalized_index -= -array_length
    end

    return normalized_index
end

@inline function _counts_get_direct(h::AbstractHistogram, index)
    return @inbounds h.counts[index+1]
end

@inline function _counts_get_normalised(h::AbstractHistogram, index)
    return _counts_get_direct(h, _normalize_index(h, index))
end

@inline function _counts_inc_direct!(h::AbstractHistogram, index, value)
    return @inbounds h.counts[index+1] += value
end

@inline function _counts_inc_normalised!(h::AbstractHistogram, index, value)
    normalised_index = _normalize_index(h, index)
    _counts_inc_direct!(h, normalised_index, value)
    _total_count_inc!(h, value)
end

@inline function _update_min_max!(h::AbstractHistogram, value)
    h.min_value = min(h.min_value, value)
    h.max_value = max(h.max_value, value)
end

#### UTILITIES ####

function _get_bucket_index(h::AbstractHistogram, value)
    return h.leading_zero_count_base - leading_zeros(value | h.sub_bucket_mask)
end

function _get_sub_bucket_index(value, bucket_index, unit_magnitude)
    return value >> ((bucket_index + unit_magnitude) % 64)
end

function _counts_index(h::AbstractHistogram, bucket_index, sub_bucket_index)
    bucket_base_index = (bucket_index + 1) << (h.sub_bucket_half_count_magnitude % 64) # Calculate the index for the first entry in the bucket
    offset_in_bucket = sub_bucket_index - h.sub_bucket_half_count # Calculate the offset in the bucket
    return bucket_base_index + offset_in_bucket
end

function _value_from_index(bucket_index, sub_bucket_index, unit_magnitude)
    return Int64(sub_bucket_index) << ((bucket_index + unit_magnitude) % 64)
end

function _counts_index_for(h::AbstractHistogram, value)
    bucket_index = _get_bucket_index(h, value)
    sub_bucket_index = _get_sub_bucket_index(value, bucket_index, h.unit_magnitude)
    return _counts_index(h, bucket_index, sub_bucket_index)
end

function value_at_index(h::AbstractHistogram, index::Integer)
    bucket_index = (index >> (h.sub_bucket_half_count_magnitude % 64)) - 1
    sub_bucket_index = (index & (h.sub_bucket_half_count - 1)) + h.sub_bucket_half_count

    if bucket_index < 0
        sub_bucket_index -= h.sub_bucket_half_count
        bucket_index = 0
    end

    return _value_from_index(bucket_index, sub_bucket_index, h.unit_magnitude)
end

function size_of_equivalent_value_range(h::AbstractHistogram, value::Int64)
    bucket_index = _get_bucket_index(h, value)
    sub_bucket_index = _get_sub_bucket_index(value, bucket_index, h.unit_magnitude)
    adjusted_bucket = (sub_bucket_index >= h.sub_bucket_count) ? (bucket_index + 1) : bucket_index
    return 1 << ((h.unit_magnitude + adjusted_bucket) % 64)
end

function _size_of_equivalent_value_range_given_bucket_indices(h::AbstractHistogram, bucket_index, sub_bucket_index)
    adjusted_bucket = (sub_bucket_index >= h.sub_bucket_count) ? (bucket_index + 1) : bucket_index
    return 1 << ((h.unit_magnitude + adjusted_bucket) % 64)
end

function _lowest_equivalent_value(h::AbstractHistogram, value)
    bucket_index = _get_bucket_index(h, value)
    sub_bucket_index = _get_sub_bucket_index(value, bucket_index, h.unit_magnitude)
    return _value_from_index(bucket_index, sub_bucket_index, h.unit_magnitude)
end

function _lowest_equivalent_value_given_bucket_indices(h::AbstractHistogram, bucket_index, sub_bucket_index)
    return _value_from_index(bucket_index, sub_bucket_index, h.unit_magnitude)
end

function next_non_equivalent_value(h::AbstractHistogram, value::Int64)
    return _lowest_equivalent_value(h, value) + size_of_equivalent_value_range(h, value)
end

function _highest_equivalent_value(h::AbstractHistogram, value)
    return next_non_equivalent_value(h, value) - 1
end

function median_equivalent_value(h::AbstractHistogram, value::Int64)
    return _lowest_equivalent_value(h, value) + (size_of_equivalent_value_range(h, value) >> 1)
end

function _non_zero_min(h::AbstractHistogram{C}) where {C}
    if _min_value(h) == typemax(C)
        return typemax(C)
    end
    return _lowest_equivalent_value(h, _min_value(h))
end

function reset_internal_counters!(h::AbstractHistogram{C}) where {C}
    min_non_zero_index = -1
    max_index = -1
    observed_total_count = 0

    for i in eachindex(h.counts)
        if (count = _counts_get_direct(h, i)) > 0
            observed_total_count += count
            max_index = i
            if min_non_zero_index == -1 && i != 1
                min_non_zero_index = i
            end
        end
    end

    if max_index == -1
        _max_value!(h, 0)
    else
        max_value = value_at_index(h, max_index)
        _max_value!(h, _highest_equivalent_value(h, max_value))
    end

    if min_non_zero_index == -1
        _min_value!(h, typemax(C))
    else
        _min_value!(h, value_at_index(h, min_non_zero_index))
    end

    _total_count!(h, observed_total_count)
end

function _buckets_needed_to_cover_value(C::Type{<:Integer}, value, sub_bucket_count, unit_magnitude)
    smallest_untrackable_value = Int64(sub_bucket_count) << (unit_magnitude % 64)
    buckets_needed = 1
    while smallest_untrackable_value <= value
        if smallest_untrackable_value > typemax(C) ÷ 2
            return buckets_needed + 1
        end
        smallest_untrackable_value <<= 1
        buckets_needed += 1
    end
    return buckets_needed
end

#### UPDATES ####

@inline function record_value!(h::AbstractHistogram, value::Int64)
    record_values!(h, value, 1)
end

@inline function record_values!(h::AbstractHistogram, value::Int64, count::Int64)
    value < 0 && throw(ArgumentError("value $value must be >= 0"))
    count <= 0 && throw(ArgumentError("count $count must be > 0"))

    counts_index = _counts_index_for(h, value)
    if counts_index >= length(h.counts)
        if _auto_resize(h)
            _resize!(h, value)
        else
            throw(ArgumentError("value $value outside of histogram range"))
        end
    end

    _counts_inc_normalised!(h, counts_index, count)
    _update_min_max!(h, value)
end

@inline function record_corrected_value!(h::AbstractHistogram, value::Int64, expected_interval::Int64)
    record_corrected_values!(h, value, 1, expected_interval)
end

@inline function record_corrected_values!(h::AbstractHistogram, value::Int64, count::Int64, expected_interval::Int64)
    record_values!(h, value, count)

    if !(0 < expected_interval < value)
        return
    end

    missing_value = value - expected_interval
    while missing_value >= expected_interval
        record_values!(h, missing_value, count)
        missing_value -= expected_interval
    end
end

function add(h::AbstractHistogram, from::AbstractHistogram)
    iter = iter_recorded_init(from)
    while iter_next(iter)
        value = value(iter)
        count = count(iter)
        record_values!(h, value, count)
    end
end

function add_while_correcting_for_coordinated_omission(h::AbstractHistogram, from::AbstractHistogram, expected_interval::Int64)
    iter = iter_recorded_init(from)
    while iter_next(iter)
        value = value(iter)
        count = count(iter)
        record_corrected_values!(h, value, count, expected_interval)
    end
end

#### VALUES ####

function Base.max(h::AbstractHistogram{C}) where {C}
    if _max_value(h) == zero(C)
        return 0
    end
    return _highest_equivalent_value(h, _max_value(h))
end

function Base.min(h::AbstractHistogram{C}) where {C}
    if count_at_index(h, 0) > zero(C)
        return 0
    end
    return _non_zero_min(h)
end

function _get_value_from_index_up_to_count(h::AbstractHistogram, count_at_percentile)
    count_to_index = 0
    count_at_percentile = count_at_percentile > 0 ? count_at_percentile : 1
    for idx in eachindex(h.counts)
        count_to_index += _counts_get_direct(h, idx)
        if count_to_index >= count_at_percentile
            return value_at_index(h, idx)
        end
    end
    return 0
end

function value_at_percentile(h::AbstractHistogram, percentile::Float64)
    requested_percentile = clamp(percentile, 0.0, 100.0)
    count_at_percentile = round(Int64, (requested_percentile / 100) * _total_count(h))
    value_from_index = _get_value_from_index_up_to_count(h, count_at_percentile)
    if percentile == 0.0
        return _lowest_equivalent_value(h, value_from_index)
    end
    return _highest_equivalent_value(h, value_from_index)
end

function value_at_percentiles(h::AbstractHistogram, percentiles::Vector{Float64}, values::Vector{Int64})
    total_count = _total_count(h)
    for i in eachindex(percentiles)
        requested_percentile = clamp(percentiles[i], 0.0, 100.0)
        count_at_percentile = round(Int64, (requested_percentile / 100) * total_count)
        values[i] = count_at_percentile > 1 ? count_at_percentile : 1
    end
    iter = iter_init(h)
    total = 0
    at_pos = 1
    while iter_next(iter) && at_pos <= length(percentiles)
        total += iter.count
        while at_pos <= length(percentiles) && total >= values[at_pos]
            values[at_pos] = _highest_equivalent_value(h, iter.value)
            at_pos += 1
        end
    end
    return 0
end

function mean(h::AbstractHistogram{C}) where {C}
    total = 0
    count = 0
    total_count = _total_count(h)
    if total_count == zero(C)
        return 0.0
    end
    iter = iter_init(h)
    while iter_next(iter) && count < total_count
        if iter.count != 0
            count += iter.count
            total += iter.count * median_equivalent_value(h, iter.value)
        end
    end
    return total / total_count
end

function stddev(h::AbstractHistogram{C}) where {C}
    total_count = _total_count(h)
    if total_count == zero(C)
        return 0.0
    end
    mean = mean(h)
    geometric_dev_total = 0.0
    iter = iter_init(h)
    while iter_next(iter)
        if iter.count != 0
            dev = median_equivalent_value(h, iter.value) - mean
            geometric_dev_total += dev^2 * iter.count
        end
    end
    return sqrt(geometric_dev_total / total_count)
end

function values_are_equivalent(h::AbstractHistogram, a::Int64, b::Int64)
    return _lowest_equivalent_value(h, a) == _lowest_equivalent_value(h, b)
end

function lowest_equivalent_value(h::AbstractHistogram, value::Int64)
    return _lowest_equivalent_value(h, value)
end

function count_at_value(h::AbstractHistogram, value::Int64)
    index < 0 && throw(ArgumentError("value $value must be >= 0"))
    return _counts_get_normalised(h, _counts_index_for(h, value))
end

function count_at_index(h::AbstractHistogram, index::Int64)
    index < 0 && throw(ArgumentError("index $index must be >= 0"))
    return _counts_get_normalised(h, index)
end

#### ITERATORS ####
