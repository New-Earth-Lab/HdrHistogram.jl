using Atomix: @atomic

mutable struct AtomicHistogram{T<:Signed} <: AbstractHistogram{T}
    lowest_discernible_value::Int64
    highest_trackable_value::Int64
    unit_magnitude::UInt64
    significant_figures::Int64
    sub_bucket_half_count_magnitude::UInt64
    sub_bucket_half_count::Int64
    sub_bucket_mask::Int64
    sub_bucket_count::Int64
    bucket_count::Int64
    @atomic min_value::Int64
    @atomic max_value::Int64
    normalizing_index_offset::Int64
    conversion_ratio::Float64
    @atomic total_count::Int64
    @atomic counts::Vector{T}
end

function AtomicHistogram(T::Type{<:Real}, lowest_discernible_value::Int64, highest_trackable_value::Int64, significant_figures::Int32)
    return init(AtomicHistogram{T}, lowest_discernible_value, highest_trackable_value, significant_figures)
end

function AtomicHistogram(lowest_discernible_value, highest_trackable_value, significant_figures)
    return init(AtomicHistogram{Int64}, lowest_discernible_value, highest_trackable_value, significant_figures)
end

total_count(h::AtomicHistogram) = @atomic h.total_count
total_count!(h::AtomicHistogram, value) = @atomic h.total_count = value
min_value(h::AtomicHistogram) = @atomic h.min_value
min_value!(h::AtomicHistogram, value) = @atomic h.min_value = value
max_value(h::AtomicHistogram) = @atomic h.max_value
max_value!(h::AtomicHistogram, value) = @atomic h.max_value = value

@inline function counts_get_direct(h::AtomicHistogram, index)
    return @inbounds @atomic h.counts[index+1]
end

@inline function update_min_max!(h::AtomicHistogram, value)
    @atomic min(h.min_value, value)
    @atomic max(h.max_value, value)
end

@inline function counts_inc_normalised!(h::AtomicHistogram, index, value)
    normalised_index = normalize_index(h, index)
    @inbounds @atomic h.counts[normalised_index+1] += value
    @atomic h.total_count += value
end
