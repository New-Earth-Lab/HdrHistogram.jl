mutable struct Histogram{C<:Signed} <: AbstractHistogram{C}
    const lowest_discernible_value::Int64
    highest_trackable_value::Int64
    const unit_magnitude::UInt64
    const significant_figures::Int64
    const sub_bucket_half_count_magnitude::UInt64
    const sub_bucket_half_count::Int64
    const sub_bucket_mask::Int64
    const sub_bucket_count::Int64
    const leading_zero_count_base::Int64
    bucket_count::Int64
    min_value::Int64
    max_value::Int64
    const normalizing_index_offset::Int64
    const conversion_ratio::Float64
    const auto_resize::Bool
    total_count::Int64
    counts::Vector{C}
end

"""
    Histogram(C::Type{<:Signed}, lowest_discernible_value, highest_trackable_value, significant_figures)

Constructs a new histogram with the specified configuration.

# Arguments
- `C`: The type of the histogram's counters, which must be a subtype of `Signed`.
- `lowest_discernible_value`: The lowest value that can be discerned (distinguished from zero) by the histogram.
- `highest_trackable_value`: The highest value that can be tracked (distinguished from infinity) by the histogram.
- `significant_figures`: The number of significant decimal digits to which the histogram will maintain value resolution and separation.

"""
function Histogram(C::Type{<:Signed}, lowest_discernible_value, highest_trackable_value, significant_figures)
    return _init(Histogram{C}, lowest_discernible_value, highest_trackable_value, significant_figures, false)
end

"""
    Histogram(lowest_discernible_value, highest_trackable_value, significant_figures)

Constructs a new histogram with the specified configuration.

# Arguments
- `lowest_discernible_value`: The lowest value that can be discerned (distinguished from zero) by the histogram.
- `highest_trackable_value`: The highest value that can be tracked (distinguished from infinity) by the histogram.
- `significant_figures`: The number of significant decimal digits to which the histogram will maintain value resolution and separation.

"""
function Histogram(lowest_discernible_value, highest_trackable_value, significant_figures)
    return _init(Histogram{Int64}, lowest_discernible_value, highest_trackable_value, significant_figures, false)
end

"""
    Histogram(numberOfSignificantValueDigits)

Construct an auto-resizing histogram with a lowest discernible value of 1 and an auto-adjusting
highestTrackableValue. Can auto-resize up to track values up to (typemax(Int64) / 2).

# Arguments
- `numberOfSignificantValueDigits::Int`: The number of significant decimal digits to which the histogram will
    maintain value resolution and separation. Must be a non-negative.

"""
function Histogram(significant_figures)
    return _init(Histogram{Int64}, 1, 2, significant_figures, true)
end
