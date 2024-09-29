mutable struct Histogram{C} <: AbstractHistogram{C}
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

lowest_discernible_value(h::Histogram) = h.lowest_discernible_value

highest_trackable_value(h::Histogram) = h.highest_trackable_value
highest_trackable_value!(h::Histogram, value) = h.highest_trackable_value = value

unit_magnitude(h::Histogram) = h.unit_magnitude

significant_figures(h::Histogram) = h.significant_figures

sub_bucket_half_count_magnitude(h::Histogram) = h.sub_bucket_half_count_magnitude

sub_bucket_half_count(h::Histogram) = h.sub_bucket_half_count

sub_bucket_mask(h::Histogram) = h.sub_bucket_mask

sub_bucket_count(h::Histogram) = h.sub_bucket_count

leading_zero_count_base(h::Histogram) = h.leading_zero_count_base

bucket_count(h::Histogram) = h.bucket_count
bucket_count!(h::Histogram, value) = h.bucket_count = value

min_value(h::Histogram) = h.min_value
min_value!(h::Histogram, value) = h.min_value = value

max_value(h::Histogram) = h.max_value
max_value!(h::Histogram, value) = h.max_value = value

normalizing_index_offset(h::Histogram) = h.normalizing_index_offset

conversion_ratio(h::Histogram) = h.conversion_ratio

auto_resize(h::Histogram) = h.auto_resize

total_count(h::Histogram) = h.total_count
total_count!(h::Histogram, value) = h.total_count = value
total_count_inc!(h::Histogram, value) = h.total_count += value

counts(h::Histogram) = h.counts
counts!(h::Histogram, value) = h.counts = value
counts_length(h::Histogram) = length(h.counts)

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
