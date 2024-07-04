abstract type AbstractHistogram{C} end

#### MEMORY ####

function _init(H::Type{<:AbstractHistogram{C}},
    lowest_discernible_value::Int64,
    highest_trackable_value::Int64,
    significant_figures::Int64,
    auto_resize::Bool) where {C}
    if !(0 < significant_figures <= 5)
        throw(ArgumentError("number of significant_figures must be between 0 and 5"))
    end

    if !(1 <= lowest_discernible_value <= (typemax(Int64) ÷ 2))
        throw(ArgumentError("lowest_discernible_value >=1 and <= $(typemax(Int64) ÷ 2)"))
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

    bucket_count = buckets_needed_to_cover_value(C, highest_trackable_value, sub_bucket_count, unit_magnitude)
    counts_len = (bucket_count + 1) * sub_bucket_half_count

    return H(lowest_discernible_value, highest_trackable_value, unit_magnitude,
        significant_figures, sub_bucket_half_count_magnitude,
        sub_bucket_half_count, sub_bucket_mask, sub_bucket_count, leading_zero_count_base,
        bucket_count, typemax(C), 0, 0, 1.0, auto_resize, 0, zeros(C, counts_len))
end

function reset!(h::AbstractHistogram{C}) where {C}
    total_count!(h, 0)
    min_value!(h, typemax(C))
    max_value!(h, 0)
    fill!(counts(h), 0)
end

### COUNTS ###

function resize!(h::AbstractHistogram{C}, highest_trackable_value) where {C}
    if !(highest_trackable_value >= lowest_discernible_value(h) * 2)
        throw(ArgumentError("highest_trackable_value must be >= 2 * lowest_discernible_value"))
    end
    bucket_count = buckets_needed_to_cover_value(C, highest_trackable_value, sub_bucket_count(h), unit_magnitude(h))
    counts_len = (bucket_count + 1) * sub_bucket_half_count(h)
    old_len = counts_length(h)
    resize!(counts(h), counts_len)
    fill!(view(counts(h), old_len+1:counts_len), 0)
    bucket_count!(h, bucket_count)
    highest_trackable_value!(h, highest_trackable_value)
end

@inline function normalize_index(h::AbstractHistogram, index)
    if normalizing_index_offset(h) == 0
        return index
    end

    normalized_index = index - normalizing_index_offset(h)

    array_length = counts_length(h)
    if normalized_index < 0
        normalized_index += array_length
    elseif normalized_index >= array_length
        normalized_index -= -array_length
    end

    return normalized_index
end

@inline function counts_get_direct(h::AbstractHistogram, index)
    return @inbounds counts(h)[index+1]
end

@inline function counts_get_normalised(h::AbstractHistogram, index)
    return counts_get_direct(h, normalize_index(h, index))
end

@inline function counts_inc_direct!(h::AbstractHistogram, index, value)
    return @inbounds counts(h)[index+1] += value
end

@inline function counts_inc_normalised!(h::AbstractHistogram, index, value)
    normalised_index = normalize_index(h, index)
    counts_inc_direct!(h, normalised_index, value)
    total_count_inc!(h, value)
end

@inline function update_min_max!(h::AbstractHistogram, value)
    min_value!(h, min(min_value(h), value))
    max_value!(h, max(max_value(h), value))
end

#### UTILITIES ####

function get_bucket_index(h::AbstractHistogram, value)
    return leading_zero_count_base(h) - leading_zeros(value | sub_bucket_mask(h))
end

function get_sub_bucket_index(value, bucket_index, unit_magnitude)
    return value >> ((bucket_index + unit_magnitude) % 64)
end

function counts_index(h::AbstractHistogram, bucket_index, sub_bucket_index)
    # Calculate the index for the first entry in the bucket
    bucket_base_index = (bucket_index + 1) << (sub_bucket_half_count_magnitude(h) % 64)
    # Calculate the offset in the bucket
    offset_in_bucket = sub_bucket_index - sub_bucket_half_count(h)
    return bucket_base_index + offset_in_bucket
end

function value_from_index(bucket_index, sub_bucket_index, unit_magnitude)
    return Int64(sub_bucket_index) << ((bucket_index + unit_magnitude) % 64)
end

function counts_index_for(h::AbstractHistogram, value)
    bucket_index = get_bucket_index(h, value)
    sub_bucket_index = get_sub_bucket_index(value, bucket_index, unit_magnitude(h))
    return counts_index(h, bucket_index, sub_bucket_index)
end

function value_at_index(h::AbstractHistogram, index::Int64)
    bucket_index = (index >> (sub_bucket_half_count_magnitude(h) % 64)) - 1
    sub_bucket_index = (index & (sub_bucket_half_count(h) - 1)) + sub_bucket_half_count(h)

    if bucket_index < 0
        sub_bucket_index -= sub_bucket_half_count(h)
        bucket_index = 0
    end

    return value_from_index(bucket_index, sub_bucket_index, unit_magnitude(h))
end

function size_of_equivalent_value_range(h::AbstractHistogram, value::Int64)
    bucket_index = get_bucket_index(h, value)
    sub_bucket_index = get_sub_bucket_index(value, bucket_index, unit_magnitude(h))
    adjusted_bucket = (sub_bucket_index >= sub_bucket_count(h)) ? (bucket_index + 1) : bucket_index
    return 1 << ((unit_magnitude(h) + adjusted_bucket) % 64)
end

function size_of_equivalent_value_range_given_bucket_indices(h::AbstractHistogram, bucket_index, sub_bucket_index)
    adjusted_bucket = (sub_bucket_index >= sub_bucket_count(h)) ? (bucket_index + 1) : bucket_index
    return 1 << ((unit_magnitude(h) + adjusted_bucket) % 64)
end

function lowest_equivalent_value(h::AbstractHistogram, value)
    bucket_index = get_bucket_index(h, value)
    sub_bucket_index = get_sub_bucket_index(value, bucket_index, unit_magnitude(h))
    return value_from_index(bucket_index, sub_bucket_index, unit_magnitude(h))
end

function lowest_equivalent_value_given_bucket_indices(h::AbstractHistogram, bucket_index, sub_bucket_index)
    return value_from_index(bucket_index, sub_bucket_index, unit_magnitude(h))
end

function next_non_equivalent_value(h::AbstractHistogram, value::Int64)
    return lowest_equivalent_value(h, value) + size_of_equivalent_value_range(h, value)
end

function highest_equivalent_value(h::AbstractHistogram, value)
    return next_non_equivalent_value(h, value) - 1
end

function median_equivalent_value(h::AbstractHistogram, value::Int64)
    return lowest_equivalent_value(h, value) + (size_of_equivalent_value_range(h, value) >> 1)
end

function reset_internal_counters!(h::AbstractHistogram{C}) where {C}
    min_non_zero_index = -1
    max_index = -1
    observed_total_count = 0

    # For compatability all indicies are 0-based
    for i in 0:counts_length-1
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
        max_value = value_at_index(h, max_index)
        max_value!(h, highest_equivalent_value(h, max_value))
    end

    if min_non_zero_index == -1
        min_value!(h, typemax(C))
    else
        min_value!(h, value_at_index(h, min_non_zero_index))
    end

    total_count!(h, observed_total_count)
end

function buckets_needed_to_cover_value(C::Type{<:Integer}, value, sub_bucket_count, unit_magnitude)
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

@inline function record_value!(h::AbstractHistogram, value::Int64, count::Int64=1)
    value >= 0 || throw(ArgumentError("value $value must be >= 0"))
    count > 0 || throw(ArgumentError("count $count must be > 0"))

    counts_index = counts_index_for(h, value)
    if counts_index >= counts_length(h)
        if auto_resize(h)
            resize!(h, value)
        else
            throw(ArgumentError("value $value outside of histogram range"))
        end
    end

    counts_inc_normalised!(h, counts_index, count)
    update_min_max!(h, value)
end

@inline function record_corrected_value!(h::AbstractHistogram, value::Int64, expected_interval::Int64, count::Int64=1)
    record_value!(h, value, count)

    if value <= expected_interval || expected_interval <= 0
        return
    end

    missing_value = value - expected_interval
    while missing_value >= expected_interval
        record_value!(h, missing_value, count)
        missing_value -= expected_interval
    end
end

function add(h::AbstractHistogram, from::AbstractHistogram)
    for i in RecordedValuesIterator(from)
        record_value!(h, value(i), count(i))
    end
end

function add_while_correcting_for_coordinated_omission(h::AbstractHistogram, from::AbstractHistogram, expected_interval::Int64)
    for i in RecordedValuesIterator(from)
        record_corrected_value!(h, value(i), expected_interval, count(i))
    end
end

#### VALUES ####

function Base.max(h::AbstractHistogram{C}) where {C}
    if max_value(h) == zero(C)
        return 0
    end
    return highest_equivalent_value(h, max_value(h))
end

function Base.min(h::AbstractHistogram{C}) where {C}
    if count_at_index(h, 0) > zero(C)
        return 0
    end

    if min_value(h) == typemax(C)
        return typemax(C)
    end

    return lowest_equivalent_value(h, min_value(h))
end

function count_at_percentile(h::AbstractHistogram{C}, percentile::Real) where {C}
    # Truncate to 0..100%, and remove 1 unit of least precision to avoid roundoff overruns into next bucket when we
    # subsequently round up to the nearest integer:
    requested_percentile = prevfloat(clamp(percentile, 0.0, 100.0))

    # Derive the count at the requested percentile. We round up to nearest integer to ensure that the
    # largest value that the requested percentile of overall recorded values is <= is actually included.
    return max(ceil(C, requested_percentile * total_count(h) / 100.0), 1)
end

function value_at_percentile(h::AbstractHistogram, percentile::Real)
    count = count_at_percentile(h, percentile)

    for i in RecordedValuesIterator(h)
        if total_count_to_this_value(i) >= count
            return percentile == zero(typeof(percentile)) ?
                   lowest_equivalent_value(h, value(i)) : highest_equivalent_value(h, value(i))
        end
    end
    return 0
end

function value_at_percentile(h::AbstractHistogram, percentiles, values::AbstractVector{<:Number})
    if length(percentiles) != length(values)
        throw(ArgumentError("percentiles and values must have the same length"))
    end

    # to avoid allocations we use the values array for intermediate computation
    # i.e. to store the expected cumulative count at each percentile
    for i in eachindex(percentiles)
        values[i] = count_at_percentile(h, percentiles[i])
    end
    at_pos = 1

    for i in RecordedValuesIterator(h)
        if at_pos > length(percentiles)
            break
        end

        while at_pos <= length(percentiles) && total_count_to_this_value(i) >= values[at_pos]
            values[at_pos] = percentiles[at_pos] == zero(eltype(percentiles)) ?
                             lowest_equivalent_value(h, value(i)) : highest_equivalent_value(h, value(i))
            at_pos += 1
        end
    end
end

function value_at_percentile(h::AbstractHistogram{C}, percentiles::AbstractVector) where {C}
    values = zeros(C, length(percentiles))
    value_at_percentile(h, percentiles, values)
    return values
end

function mean(h::AbstractHistogram{C}) where {C}
    total = 0
    count_total = total_count(h)
    if count_total == zero(C)
        return 0.0
    end
    for i in RecordedValuesIterator(h)
        total += count(i) * median_equivalent_value(h, value(i))
    end
    return total / count_total
end

function stddev(h::AbstractHistogram{C}) where {C}
    count_total = total_count(h)
    if count_total == zero(C)
        return 0.0
    end
    m = mean(h)
    geometric_dev_total = 0.0
    for i in RecordedValuesIterator(h)
        dev = median_equivalent_value(h, value(i)) - m
        geometric_dev_total += dev^2 * count(i)
    end
    return sqrt(geometric_dev_total / count_total)
end

function values_are_equivalent(h::AbstractHistogram, a::Int64, b::Int64)
    return lowest_equivalent_value(h, a) == lowest_equivalent_value(h, b)
end

function count_at_value(h::AbstractHistogram, value::Int64)
    value >= 0 || throw(ArgumentError("value $value must be >= 0"))
    return counts_get_normalised(h, counts_index_for(h, value))
end

function count_at_index(h::AbstractHistogram, index::Int64)
    index >= 0 || throw(ArgumentError("index $index must be >= 0"))
    return counts_get_normalised(h, index)
end

function percentile_print(io::IO, h::AbstractHistogram, ticks_per_half_distance, value_scale)
    @printf(io, "%12s %12s %12s %12s\n\n", "Value", "Percentile", "TotalCount", "1/(1-Percentile)")
    for i in PercentileIterator(h, ticks_per_half_distance)
        val = highest_equivalent_value(h, value(i)) / value_scale
        p = percentile(i) / 100.0
        total_count = total_count_to_this_value(i)
        inverted_percentile = 1.0 / (1.0 - p)
        @printf(io, "%12.5f %12f %12d %12.2f\n", val, p, total_count, inverted_percentile)
    end
    mean = HdrHistogram.mean(h) / value_scale
    stddev = HdrHistogram.stddev(h) / value_scale
    max = HdrHistogram.max(h) / value_scale

    @printf(io, "#[Mean    = %12.3f, StdDeviation   = %12.3f]\n", mean, stddev)
    @printf(io, "#[Max     = %12.3f, Total count    = %12d]\n", max, total_count(h))
    @printf(io, "#[Buckets = %12d, SubBuckets     = %12d]\n", bucket_count(h), sub_bucket_count(h))
end
