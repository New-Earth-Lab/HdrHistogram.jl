mutable struct Histogram{T<:Signed} <: AbstractHistogram{T}
    lowest_discernible_value::Int64
    highest_trackable_value::Int64
    unit_magnitude::UInt64
    significant_figures::Int64
    sub_bucket_half_count_magnitude::UInt64
    sub_bucket_half_count::Int64
    sub_bucket_mask::Int64
    sub_bucket_count::Int64
    bucket_count::Int64
    min_value::Int64
    max_value::Int64
    normalizing_index_offset::Int64
    conversion_ratio::Float64
    total_count::Int64
    counts::Vector{T}
end

function Histogram(T::Type{<:Real}, lowest_discernible_value, highest_trackable_value, significant_figures)
    return init(Histogram{T}, lowest_discernible_value, highest_trackable_value, significant_figures)
end

function Histogram(lowest_discernible_value, highest_trackable_value, significant_figures)
    return init(Histogram{Int64}, lowest_discernible_value, highest_trackable_value, significant_figures)
end

