mutable struct HistogramIteratorBaseState
    total_count::Int64
    current_index::Int64
    current_value_at_index::Int64
    next_value_at_index::Int64
    previous_value_iterated_to::Int64
    total_count_to_previous_index::Int64
    total_count_to_current_index::Int64
    total_value_to_current_index::Int64
    count_at_this_value::Int64
    fresh_sub_bucket::Bool
end

total_count(s::HistogramIteratorBaseState) = s.total_count
total_count!(s::HistogramIteratorBaseState, value) = s.total_count = value
current_index(s::HistogramIteratorBaseState) = s.current_index
current_index!(s::HistogramIteratorBaseState, value) = s.current_index = value
current_value_at_index(s::HistogramIteratorBaseState) = s.current_value_at_index
current_value_at_index!(s::HistogramIteratorBaseState, value) = s.current_value_at_index = value
next_value_at_index(s::HistogramIteratorBaseState) = s.next_value_at_index
next_value_at_index!(s::HistogramIteratorBaseState, value) = s.next_value_at_index = value
previous_value_iterated_to(s::HistogramIteratorBaseState) = s.previous_value_iterated_to
previous_value_iterated_to!(s::HistogramIteratorBaseState, value) = s.previous_value_iterated_to = value
total_count_to_previous_index(s::HistogramIteratorBaseState) = s.total_count_to_previous_index
total_count_to_previous_index!(s::HistogramIteratorBaseState, value) = s.total_count_to_previous_index = value
total_count_to_current_index(s::HistogramIteratorBaseState) = s.total_count_to_current_index
total_count_to_current_index!(s::HistogramIteratorBaseState, value) = s.total_count_to_current_index = value
total_value_to_current_index(s::HistogramIteratorBaseState) = s.total_value_to_current_index
total_value_to_current_index!(s::HistogramIteratorBaseState, value) = s.total_value_to_current_index = value
count_at_this_value(s::HistogramIteratorBaseState) = s.count_at_this_value
count_at_this_value!(s::HistogramIteratorBaseState, value) = s.count_at_this_value = value
fresh_sub_bucket(s::HistogramIteratorBaseState) = s.fresh_sub_bucket
fresh_sub_bucket!(s::HistogramIteratorBaseState, value) = s.fresh_sub_bucket = value

HistogramIteratorBaseState(iter::AbstractHistogramIterator) = HistogramIteratorBaseState(total_count(histogram(iter)),
    0, 0, 1 << unit_magnitude(histogram(iter)), 0, 0, 0, 0, 0, true)

mutable struct AllValuesIteratorState <: AbstractHistogramIteratorState
    state::HistogramIteratorBaseState
    visited_index::Int64
    AllValuesIteratorState(h::AbstractHistogram) = new(HistogramIteratorBaseState(h), 0)
end

struct AllValuesIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
end
histogram(iter::AllValuesIterator) = iter.histogram
state(iter::AllValuesIterator) = iter.state

total_count(s::AllValuesIteratorState) = total_count(getfield(s, :state))
total_count!(s::AllValuesIteratorState, value) = total_count!(getfield(s, :state), value)

current_index(s::AllValuesIteratorState) = current_index(getfield(s, :state))
current_index!(s::AllValuesIteratorState, value) = current_index!(getfield(s, :state), value)

current_value_at_index(s::AllValuesIteratorState) = current_value_at_index(getfield(s, :state))
current_value_at_index!(s::AllValuesIteratorState, value) = current_value_at_index!(getfield(s, :state), value)

next_value_at_index(s::AllValuesIteratorState) = next_value_at_index(getfield(s, :state))
next_value_at_index!(s::AllValuesIteratorState, value) = next_value_at_index!(getfield(s, :state), value)

previous_value_iterated_to(s::AllValuesIteratorState) = previous_value_iterated_to(getfield(s, :state))
previous_value_iterated_to!(s::AllValuesIteratorState, value) = previous_value_iterated_to!(getfield(s, :state), value)

total_count_to_previous_index(s::AllValuesIteratorState) = total_count_to_previous_index(getfield(s, :state))
total_count_to_previous_index!(s::AllValuesIteratorState, value) = total_count_to_previous_index!(getfield(s, :state), value)

total_count_to_current_index(s::AllValuesIteratorState) = total_count_to_current_index(getfield(s, :state))
total_count_to_current_index!(s::AllValuesIteratorState, value) = total_count_to_current_index!(getfield(s, :state), value)

total_value_to_current_index(s::AllValuesIteratorState) = total_value_to_current_index(getfield(s, :state))
total_value_to_current_index!(s::AllValuesIteratorState, value) = total_value_to_current_index!(getfield(s, :state), value)

count_at_this_value(s::AllValuesIteratorState) = count_at_this_value(getfield(s, :state))
count_at_this_value!(s::AllValuesIteratorState, value) = count_at_this_value!(getfield(s, :state), value)

fresh_sub_bucket(s::AllValuesIteratorState) = fresh_sub_bucket(getfield(s, :state))
fresh_sub_bucket!(s::AllValuesIteratorState, value) = fresh_sub_bucket!(getfield(s, :state), value)

function increment_iteration_level!(iter::AllValuesIterator, state::AllValuesIteratorState)
    state.visited_index = state.state.current_index
end

function reached_iteration_level(iter::AllValuesIterator, state::AllValuesIteratorState)
    return state.visited_index != state.state.current_index
end

Base.iterate(iter::AllValuesIterator) = iterate(iter, AllValuesIteratorState(iter))

struct RecordedValuesIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
end

histogram(iter::RecordedValuesIterator) = iter.histogram

mutable struct RecordedValuesIteratorState <: AbstractHistogramIteratorState
    state::HistogramIteratorBaseState
    visited_index::Int64
    RecordedValuesIteratorState(iter::AbstractHistogramIterator) = new(HistogramIteratorBaseState(iter), 0)
end

total_count(s::RecordedValuesIteratorState) = total_count(getfield(s, :state))
total_count!(s::RecordedValuesIteratorState, value) = total_count!(getfield(s, :state), value)

current_index(s::RecordedValuesIteratorState) = current_index(getfield(s, :state))
current_index!(s::RecordedValuesIteratorState, value) = current_index!(getfield(s, :state), value)

current_value_at_index(s::RecordedValuesIteratorState) = current_value_at_index(getfield(s, :state))
current_value_at_index!(s::RecordedValuesIteratorState, value) = current_value_at_index!(getfield(s, :state), value)

next_value_at_index(s::RecordedValuesIteratorState) = next_value_at_index(getfield(s, :state))
next_value_at_index!(s::RecordedValuesIteratorState, value) = next_value_at_index!(getfield(s, :state), value)

previous_value_iterated_to(s::RecordedValuesIteratorState) = previous_value_iterated_to(getfield(s, :state))
previous_value_iterated_to!(s::RecordedValuesIteratorState, value) = previous_value_iterated_to!(getfield(s, :state), value)

total_count_to_previous_index(s::RecordedValuesIteratorState) = total_count_to_previous_index(getfield(s, :state))
total_count_to_previous_index!(s::RecordedValuesIteratorState, value) = total_count_to_previous_index!(getfield(s, :state), value)

total_count_to_current_index(s::RecordedValuesIteratorState) = total_count_to_current_index(getfield(s, :state))
total_count_to_current_index!(s::RecordedValuesIteratorState, value) = total_count_to_current_index!(getfield(s, :state), value)

total_value_to_current_index(s::RecordedValuesIteratorState) = total_value_to_current_index(getfield(s, :state))
total_value_to_current_index!(s::RecordedValuesIteratorState, value) = total_value_to_current_index!(getfield(s, :state), value)

count_at_this_value(s::RecordedValuesIteratorState) = count_at_this_value(getfield(s, :state))
count_at_this_value!(s::RecordedValuesIteratorState, value) = count_at_this_value!(getfield(s, :state), value)

fresh_sub_bucket(s::RecordedValuesIteratorState) = fresh_sub_bucket(getfield(s, :state))
fresh_sub_bucket!(s::RecordedValuesIteratorState, value) = fresh_sub_bucket!(getfield(s, :state), value)

function increment_iteration_level!(iter::RecordedValuesIterator, state::RecordedValuesIteratorState)
    state.visited_index = state.state.current_index
end

function reached_iteration_level(iter::RecordedValuesIterator, state::RecordedValuesIteratorState)
    current_count = count_at_index(iter.histogram, state.state.current_index)
    return current_count != 0 && state.visited_index != state.state.current_index
end

Base.iterate(iter::RecordedValuesIterator) = iterate(iter, RecordedValuesIteratorState(iter))

struct PercentileIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
    ticks_per_half_distance::Int64
end

histogram(iter::PercentileIterator) = iter.histogram

mutable struct PercentileIteratorState <: AbstractHistogramIteratorState
    state::HistogramIteratorBaseState
    percentile_level_iterated_to::Float64
    percentile_level_iterated_from::Float64
    reached_last_recorded_value::Bool
    PercentileIteratorState(iter::AbstractHistogramIterator) = new(HistogramIteratorBaseState(iter), 0.0, 0.0, false)
end

total_count(s::PercentileIteratorState) = total_count(getfield(s, :state))
total_count!(s::PercentileIteratorState, value) = total_count!(getfield(s, :state), value)

current_index(s::PercentileIteratorState) = current_index(getfield(s, :state))
current_index!(s::PercentileIteratorState, value) = current_index!(getfield(s, :state), value)

current_value_at_index(s::PercentileIteratorState) = current_value_at_index(getfield(s, :state))
current_value_at_index!(s::PercentileIteratorState, value) = current_value_at_index!(getfield(s, :state), value)

next_value_at_index(s::PercentileIteratorState) = next_value_at_index(getfield(s, :state))
next_value_at_index!(s::PercentileIteratorState, value) = next_value_at_index!(getfield(s, :state), value)

previous_value_iterated_to(s::PercentileIteratorState) = previous_value_iterated_to(getfield(s, :state))
previous_value_iterated_to!(s::PercentileIteratorState, value) = previous_value_iterated_to!(getfield(s, :state), value)

total_count_to_previous_index(s::PercentileIteratorState) = total_count_to_previous_index(getfield(s, :state))
total_count_to_previous_index!(s::PercentileIteratorState, value) = total_count_to_previous_index!(getfield(s, :state), value)

total_count_to_current_index(s::PercentileIteratorState) = total_count_to_current_index(getfield(s, :state))
total_count_to_current_index!(s::PercentileIteratorState, value) = total_count_to_current_index!(getfield(s, :state), value)

total_value_to_current_index(s::PercentileIteratorState) = total_value_to_current_index(getfield(s, :state))
total_value_to_current_index!(s::PercentileIteratorState, value) = total_value_to_current_index!(getfield(s, :state), value)

count_at_this_value(s::PercentileIteratorState) = count_at_this_value(getfield(s, :state))
count_at_this_value!(s::PercentileIteratorState, value) = count_at_this_value!(getfield(s, :state), value)

fresh_sub_bucket(s::PercentileIteratorState) = fresh_sub_bucket(getfield(s, :state))
fresh_sub_bucket!(s::PercentileIteratorState, value) = fresh_sub_bucket!(getfield(s, :state), value)

function has_next(iter::PercentileIterator, state::PercentileIteratorState)
    if @invoke has_next(iter::AbstractHistogramIterator, state::AbstractHistogramIteratorState)
        return true
    end
    if state.reached_last_recorded_value && state.total_count > 0
        state.percentile_level_iterated_to = 100.0
        state.reached_last_recorded_value = true
        return true
    end
    return false
end

function increment_iteration_level!(iter::PercentileIterator, state::PercentileIteratorState)
    state.percentile_level_iterated_from = state.percentile_level_iterated_to

    half_distance = 2^floor(Int64, log2(100.0 / (100.0 - state.percentile_level_iterated_to)) + 1)
    percentile_reporting_ticks = half_distance * iter.ticks_per_half_distance
    state.percentile_level_iterated_to += 100.0 / percentile_reporting_ticks
end

function reached_iteration_level(iter::PercentileIterator, state::PercentileIteratorState)
    if count_at_this_value(state) == 0
        return false
    end
    current_percentile = 100.0 * total_count_to_current_index(state) / total_count(state)
    return current_percentile >= state.percentile_level_iterated_to
end

# FIXME These functions don't work as state is not accessable
function percentile_iterated_to(iter::PercentileIterator, state::PercentileIteratorState)
    return state.percentile_level_iterated_to
end

function percentile_iterated_from(iter::PercentileIterator, state::PercentileIteratorState)
    return state.percentile_level_iterated_from
end

Base.iterate(iter::PercentileIterator) = iterate(iter, PercentileIteratorState(iter))

struct LinearIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
    value_units_per_bucket::Int64
end

histogram(iter::LinearIterator) = iter.histogram

mutable struct LinearIteratorState <: AbstractHistogramIteratorState
    state::HistogramIteratorBaseState
    current_step_highest_value_reporting_level::Int64
    current_step_lowest_value_reporting_level::Int64
    LinearIteratorState(iter::LinearIterator) = new(HistogramIteratorBaseState(iter),
        iter.value_units_per_bucket,
        lowest_equivalent_value(iter.histogram, iter.value_units_per_bucket))
end

total_count(s::LinearIteratorState) = total_count(getfield(s, :state))
total_count!(s::LinearIteratorState, value) = total_count!(getfield(s, :state), value)

current_index(s::LinearIteratorState) = current_index(getfield(s, :state))
current_index!(s::LinearIteratorState, value) = current_index!(getfield(s, :state), value)

current_value_at_index(s::LinearIteratorState) = current_value_at_index(getfield(s, :state))
current_value_at_index!(s::LinearIteratorState, value) = current_value_at_index!(getfield(s, :state), value)

next_value_at_index(s::LinearIteratorState) = next_value_at_index(getfield(s, :state))
next_value_at_index!(s::LinearIteratorState, value) = next_value_at_index!(getfield(s, :state), value)

previous_value_iterated_to(s::LinearIteratorState) = previous_value_iterated_to(getfield(s, :state))
previous_value_iterated_to!(s::LinearIteratorState, value) = previous_value_iterated_to!(getfield(s, :state), value)

total_count_to_previous_index(s::LinearIteratorState) = total_count_to_previous_index(getfield(s, :state))
total_count_to_previous_index!(s::LinearIteratorState, value) = total_count_to_previous_index!(getfield(s, :state), value)

total_count_to_current_index(s::LinearIteratorState) = total_count_to_current_index(getfield(s, :state))
total_count_to_current_index!(s::LinearIteratorState, value) = total_count_to_current_index!(getfield(s, :state), value)

total_value_to_current_index(s::LinearIteratorState) = total_value_to_current_index(getfield(s, :state))
total_value_to_current_index!(s::LinearIteratorState, value) = total_value_to_current_index!(getfield(s, :state), value)

count_at_this_value(s::LinearIteratorState) = count_at_this_value(getfield(s, :state))
count_at_this_value!(s::LinearIteratorState, value) = count_at_this_value!(getfield(s, :state), value)

fresh_sub_bucket(s::LinearIteratorState) = fresh_sub_bucket(getfield(s, :state))
fresh_sub_bucket!(s::LinearIteratorState, value) = fresh_sub_bucket!(getfield(s, :state), value)

function has_next(iter::LinearIterator, state::LinearIteratorState)
    if @invoke has_next(iter::AbstractHistogramIterator, state::AbstractHistogramIteratorState)
        return true
    end
    # If next iterate does not move to the next sub bucket index (which is empty if
    # if we reached this point), then we are not done iterating... Otherwise we're done.
    return state.current_step_lowest_value_reporting_level < next_value_at_index(state)
end

function increment_iteration_level!(iter::LinearIterator, state::LinearIteratorState)
    state.current_step_highest_value_reporting_level += iter.value_units_per_bucket
    state.current_step_lowest_value_reporting_level = lowest_equivalent_value(iter.histogram, state.current_step_highest_value_reporting_level)
end

function value_iterated_to(iter::LinearIterator, state::LinearIteratorState)
    return state.current_step_highest_value_reporting_level
end

function reached_iteration_level(iter::LinearIterator, state::LinearIteratorState)
    return current_value_at_index(state) >= state.current_step_lowest_value_reporting_level
end

Base.iterate(iter::LinearIterator) = iterate(iter, LinearIteratorState(iter))

struct LogarithmicIterator{C,T<:AbstractHistogram{C}} <: AbstractHistogramIterator
    histogram::T
    value_units_per_bucket::Int64
    log_base::Float64
end

histogram(iter::LogarithmicIterator) = iter.histogram

mutable struct LogarithmicIteratorState <: AbstractHistogramIteratorState
    state::HistogramIteratorBaseState
    next_value_reporting_level::Float64
    current_step_highest_value_reporting_level::Int64
    current_step_lowest_value_reporting_level::Int64
    LogarithmicIteratorState(iter::LogarithmicIterator) = new(HistogramIteratorBaseState(iter),
        iter.value_units_per_bucket,
        iter.value_units_per_bucket,
        lowest_equivalent_value(iter.histogram, iter.value_units_per_bucket))
end

total_count(s::LogarithmicIteratorState) = total_count(getfield(s, :state))
total_count!(s::LogarithmicIteratorState, value) = total_count!(getfield(s, :state), value)

current_index(s::LogarithmicIteratorState) = current_index(getfield(s, :state))
current_index!(s::LogarithmicIteratorState, value) = current_index!(getfield(s, :state), value)

current_value_at_index(s::LogarithmicIteratorState) = current_value_at_index(getfield(s, :state))
current_value_at_index!(s::LogarithmicIteratorState, value) = current_value_at_index!(getfield(s, :state), value)

next_value_at_index(s::LogarithmicIteratorState) = next_value_at_index(getfield(s, :state))
next_value_at_index!(s::LogarithmicIteratorState, value) = next_value_at_index!(getfield(s, :state), value)

previous_value_iterated_to(s::LogarithmicIteratorState) = previous_value_iterated_to(getfield(s, :state))
previous_value_iterated_to!(s::LogarithmicIteratorState, value) = previous_value_iterated_to!(getfield(s, :state), value)

total_count_to_previous_index(s::LogarithmicIteratorState) = total_count_to_previous_index(getfield(s, :state))
total_count_to_previous_index!(s::LogarithmicIteratorState, value) = total_count_to_previous_index!(getfield(s, :state), value)

total_count_to_current_index(s::LogarithmicIteratorState) = total_count_to_current_index(getfield(s, :state))
total_count_to_current_index!(s::LogarithmicIteratorState, value) = total_count_to_current_index!(getfield(s, :state), value)

total_value_to_current_index(s::LogarithmicIteratorState) = total_value_to_current_index(getfield(s, :state))
total_value_to_current_index!(s::LogarithmicIteratorState, value) = total_value_to_current_index!(getfield(s, :state), value)

count_at_this_value(s::LogarithmicIteratorState) = count_at_this_value(getfield(s, :state))
count_at_this_value!(s::LogarithmicIteratorState, value) = count_at_this_value!(getfield(s, :state), value)

fresh_sub_bucket(s::LogarithmicIteratorState) = fresh_sub_bucket(getfield(s, :state))
fresh_sub_bucket!(s::LogarithmicIteratorState, value) = fresh_sub_bucket!(getfield(s, :state), value)

function has_next(iter::LogarithmicIterator, state::LogarithmicIteratorState)
    if @invoke has_next(iter::AbstractHistogramIterator, state::AbstractHistogramIteratorState)
        return true
    end
    # If next iterate does not move to the next sub bucket index (which is empty if
    # if we reached this point), then we are not done iterating... Otherwise we're done.
    return lowest_equivalent_value(iter.histogram, floor(Int64, state.next_value_reporting_level)) < next_value_at_index(state)
end

function increment_iteration_level!(iter::LogarithmicIterator, state::LogarithmicIteratorState)
    state.next_value_reporting_level *= iter.log_base
    state.current_step_highest_value_reporting_level = floor(state.next_value_reporting_level) - 1
    state.current_step_lowest_value_reporting_level = lowest_equivalent_value(iter.histogram, state.current_step_highest_value_reporting_level)
end

function value_iterated_to(iter::LogarithmicIterator, state::LogarithmicIteratorState)
    return state.current_step_highest_value_reporting_level
end

function reached_iteration_level(iter::LogarithmicIterator, state::LogarithmicIteratorState)
    return current_value_at_index(state) >= state.current_step_lowest_value_reporting_level
end

Base.iterate(iter::LogarithmicIterator) = iterate(iter, LogarithmicIteratorState(iter))
