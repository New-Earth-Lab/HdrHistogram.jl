using Atomix: @atomic

mutable struct AtomicHistogram{C} <: AbstractHistogram{C}
    const lowest_discernible_value::Int64
    const highest_trackable_value::Int64
    const unit_magnitude::UInt64
    const significant_figures::Int64
    const sub_bucket_half_count_magnitude::UInt64
    const sub_bucket_half_count::Int64
    const sub_bucket_mask::Int64
    const sub_bucket_count::Int64
    const leading_zero_count_base::Int64
    const bucket_count::Int64
    @atomic min_value::Int64
    @atomic max_value::Int64
    const normalizing_index_offset::Int64
    const conversion_ratio::Float64
    const auto_resize::Bool
    @atomic total_count::Int64
    @atomic counts::Vector{C}
end

lowest_discernible_value(h::AtomicHistogram) = h.lowest_discernible_value

highest_trackable_value(h::AtomicHistogram) = h.highest_trackable_value

unit_magnitude(h::AtomicHistogram) = h.unit_magnitude

significant_figures(h::AtomicHistogram) = h.significant_figures

sub_bucket_half_count_magnitude(h::AtomicHistogram) = h.sub_bucket_half_count_magnitude

sub_bucket_half_count(h::AtomicHistogram) = h.sub_bucket_half_count

sub_bucket_mask(h::AtomicHistogram) = h.sub_bucket_mask

sub_bucket_count(h::AtomicHistogram) = h.sub_bucket_count

leading_zero_count_base(h::AtomicHistogram) = h.leading_zero_count_base

bucket_count(h::AtomicHistogram) = h.bucket_count

min_value(h::AtomicHistogram) = @atomic h.min_value
min_value!(h::AtomicHistogram, value) = @atomic h.min_value = value

max_value(h::AtomicHistogram) = @atomic h.max_value
max_value!(h::AtomicHistogram, value) = @atomic h.max_value = value

normalizing_index_offset(h::AtomicHistogram) = h.normalizing_index_offset

conversion_ratio(h::AtomicHistogram) = h.conversion_ratio

auto_resize(h::AtomicHistogram) = false

total_count(h::AtomicHistogram) = @atomic h.total_count
total_count!(h::AtomicHistogram, value) = @atomic h.total_count = value
total_count_inc!(h::AtomicHistogram, value) = @atomic h.total_count += value

counts(h::AtomicHistogram) = h.counts
counts_length(h::AtomicHistogram) = length(h.counts)

"""
    AtomicHistogram(C::Type{<:Signed}, lowest_discernible_value, highest_trackable_value, significant_figures)

Constructs a new histogram with the specified configuration.

# Arguments
- `C`: The type of the histogram's counters, which must be a subtype of `Signed`.
- `lowest_discernible_value`: The lowest value that can be discerned (distinguished from zero) by the histogram.
- `highest_trackable_value`: The highest value that can be tracked (distinguished from infinity) by the histogram.
- `significant_figures`: The number of significant decimal digits to which the histogram will maintain value resolution and separation.

"""
function AtomicHistogram(C::Type{<:Signed}, lowest_discernible_value::Int64, highest_trackable_value::Int64, significant_figures::Int32)
    return _init(AtomicHistogram{C}, lowest_discernible_value, highest_trackable_value, significant_figures, false)
end

"""
    AtomicHistogram(lowest_discernible_value, highest_trackable_value, significant_figures)

Constructs a new histogram with the specified configuration.

# Arguments
- `lowest_discernible_value`: The lowest value that can be discerned (distinguished from zero) by the histogram.
- `highest_trackable_value`: The highest value that can be tracked (distinguished from infinity) by the histogram.
- `significant_figures`: The number of significant decimal digits to which the histogram will maintain value resolution and separation.

"""
function AtomicHistogram(lowest_discernible_value, highest_trackable_value, significant_figures)
    return _init(AtomicHistogram{Int64}, lowest_discernible_value, highest_trackable_value, significant_figures, false)
end

@inline function counts_get_direct(h::AtomicHistogram, index)
    i = index + 1
    return @inbounds @atomic h.counts[i]
end

@inline function counts_inc_direct!(h::AtomicHistogram, index, value)
    i = index + 1
    return @inbounds @atomic h.counts[i] += value
end

@inline function update_min_max!(h::AtomicHistogram, value)
    @atomic min(h.min_value, value)
    @atomic max(h.max_value, value)
end
