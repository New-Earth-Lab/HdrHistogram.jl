struct AllValuesIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
end
histogram(iter::AllValuesIterator) = iter.histogram

struct AllValuesIteratorState <: AbstractHistogramIteratorStateSpecific
    visited_index::Int64
end
HistogramIteratorState(iter::AllValuesIterator) = HistogramIteratorState(iter, AllValuesIteratorState(0))

function increment_iteration_level(iter::AllValuesIterator, state::HistogramIteratorState{AllValuesIteratorState})
    @reset state.specifics.visited_index = state.current_index
end

function reached_iteration_level(iter::AllValuesIterator, state::HistogramIteratorState{AllValuesIteratorState})
    return state.specifics.visited_index != state.current_index
end

struct RecordedValuesIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
end

histogram(iter::RecordedValuesIterator) = iter.histogram

struct RecordedValuesIteratorState <: AbstractHistogramIteratorStateSpecific
    visited_index::Int64
end
HistogramIteratorState(iter::RecordedValuesIterator) = HistogramIteratorState(iter, RecordedValuesIteratorState(0))

function increment_iteration_level(iter::RecordedValuesIterator, state::HistogramIteratorState{RecordedValuesIteratorState})
    @reset state.specifics.visited_index = state.current_index
end

function reached_iteration_level(iter::RecordedValuesIterator, state::HistogramIteratorState{RecordedValuesIteratorState})
    current_count = count_at_index(iter.histogram, state.current_index)
    return current_count != 0 && state.specifics.visited_index != state.current_index
end

struct PercentileIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
    ticks_per_half_distance::Int64
end

histogram(iter::PercentileIterator) = iter.histogram

struct PercentileIteratorState <: AbstractHistogramIteratorStateSpecific
    percentile_level_iterated_to::Float64
    percentile_level_iterated_from::Float64
    reached_last_recorded_value::Bool
end
HistogramIteratorState(iter::PercentileIterator) = HistogramIteratorState(iter, PercentileIteratorState(0.0, 0.0, false))

function has_next(iter::PercentileIterator, state::HistogramIteratorState{PercentileIteratorState})
    if @invoke(has_next(iter::AbstractHistogramIterator, state::AbstractHistogramIteratorState))[1]
        return true, state
    end
    if !state.specifics.reached_last_recorded_value && state.total_count > 0
        @reset state.specifics.percentile_level_iterated_to = 100.0
        @reset state.specifics.reached_last_recorded_value = true
        return true, state
    end
    return false, state
end

function increment_iteration_level(iter::PercentileIterator, state::HistogramIteratorState{PercentileIteratorState})
    @reset state.specifics.percentile_level_iterated_from = state.specifics.percentile_level_iterated_to
    percentile_gap = 100.0 - state.specifics.percentile_level_iterated_to
    if percentile_gap != 0.0
        half_distance = 2^floor(Int64, log2(100.0 / percentile_gap) + 1)
        percentile_reporting_ticks = half_distance * iter.ticks_per_half_distance
        @reset state.specifics.percentile_level_iterated_to += 100.0 / percentile_reporting_ticks
    end
    return state
end

function reached_iteration_level(iter::PercentileIterator, state::HistogramIteratorState{PercentileIteratorState})
    if state.count_at_this_value == 0
        return false
    end
    current_percentile = 100.0 * state.total_count_to_current_index / state.total_count
    return current_percentile >= state.specifics.percentile_level_iterated_to
end

function percentile_iterated_to(state::HistogramIteratorState{PercentileIteratorState})
    return state.specifics.percentile_level_iterated_to
end

function percentile_iterated_from(state::HistogramIteratorState{PercentileIteratorState})
    return state.specifics.percentile_level_iterated_from
end

struct LinearIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
    value_units_per_bucket::Int64
end

histogram(iter::LinearIterator) = iter.histogram

struct LinearIteratorState <: AbstractHistogramIteratorStateSpecific
    current_step_highest_value_reporting_level::Int64
    current_step_lowest_value_reporting_level::Int64
end
HistogramIteratorState(iter::LinearIterator) = HistogramIteratorState(iter,
    LinearIteratorState(iter.value_units_per_bucket,
        lowest_equivalent_value(iter.histogram, iter.value_units_per_bucket)))


function has_next(iter::LinearIterator, state::HistogramIteratorState{LinearIteratorState})
    if @invoke(has_next(iter::AbstractHistogramIterator, state::AbstractHistogramIteratorState))[1]
        return true, state
    end
    # If next iterate does not move to the next sub bucket index (which is empty if
    # if we reached this point), then we are not done iterating... Otherwise we're done.
    return state.specifics.current_step_lowest_value_reporting_level < state.next_value_at_index, state
end

function increment_iteration_level(iter::LinearIterator, state::HistogramIteratorState{LinearIteratorState})
    @reset state.specifics.current_step_highest_value_reporting_level += iter.value_units_per_bucket
    @reset state.specifics.current_step_lowest_value_reporting_level = lowest_equivalent_value(iter.histogram, state.specifics.current_step_highest_value_reporting_level)
end

function value_iterated_to(iter::LinearIterator, state::HistogramIteratorState{LinearIteratorState})
    return state.specifics.current_step_highest_value_reporting_level
end

function reached_iteration_level(iter::LinearIterator, state::HistogramIteratorState{LinearIteratorState})
    return state.current_value_at_index >= state.specifics.current_step_lowest_value_reporting_level
end

struct LogarithmicIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
    value_units_per_bucket::Int64
    log_base::Float64
end

histogram(iter::LogarithmicIterator) = iter.histogram

struct LogarithmicIteratorState <: AbstractHistogramIteratorStateSpecific
    next_value_reporting_level::Float64
    current_step_highest_value_reporting_level::Int64
    current_step_lowest_value_reporting_level::Int64
end
HistogramIteratorState(iter::LogarithmicIterator) = HistogramIteratorState(iter,
    LogarithmicIteratorState(iter.value_units_per_bucket,
        iter.value_units_per_bucket,
        lowest_equivalent_value(iter.histogram, iter.value_units_per_bucket)))

function has_next(iter::LogarithmicIterator, state::HistogramIteratorState{LogarithmicIteratorState})
    if @invoke(has_next(iter::AbstractHistogramIterator, state::AbstractHistogramIteratorState))[1]
        return true, state
    end
    # If next iterate does not move to the next sub bucket index (which is empty if
    # if we reached this point), then we are not done iterating... Otherwise we're done.
    return lowest_equivalent_value(iter.histogram, floor(Int64, state.specifics.next_value_reporting_level)) < state.next_value_at_index, state
end

function increment_iteration_level(iter::LogarithmicIterator, state::HistogramIteratorState{LogarithmicIteratorState})
    @reset state.specifics.next_value_reporting_level *= iter.log_base
    @reset state.specifics.current_step_highest_value_reporting_level = floor(state.specifics.next_value_reporting_level) - 1
    @reset state.specifics.current_step_lowest_value_reporting_level = lowest_equivalent_value(iter.histogram, state.specifics.current_step_highest_value_reporting_level)
end

function value_iterated_to(iter::LogarithmicIterator, state::HistogramIteratorState{LogarithmicIteratorState})
    return state.specifics.current_step_highest_value_reporting_level
end

function reached_iteration_level(iter::LogarithmicIterator, state::HistogramIteratorState{LogarithmicIteratorState})
    return state.current_value_at_index >= state.specifics.current_step_lowest_value_reporting_level
end
