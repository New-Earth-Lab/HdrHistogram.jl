abstract type AbstractHistogramIterator end

function histogram end

abstract type AbstractHistogramIteratorState end
function total_count end
function total_count! end
function current_index end
function current_index! end
function current_value_at_index end
function current_value_at_index! end
function next_value_at_index end
function next_value_at_index! end
function previous_value_iterated_to end
function previous_value_iterated_to! end
function total_count_to_previous_index end
function total_count_to_previous_index! end
function total_count_to_current_index end
function total_count_to_current_index! end
function total_value_to_current_index end
function total_value_to_current_index! end
function count_at_this_value end
function count_at_this_value! end
function fresh_sub_bucket end
function fresh_sub_bucket! end

abstract type AbstractHistogramItem end

struct HistogramIterationValue <: AbstractHistogramItem
    value_iterated_to::Int64
    value_iterated_from::Int64
    count_at_value_iterated_to::Int64
    count_added_in_this_iteration_step::Int64
    total_count_to_this_value::Int64
    total_value_to_this_value::Int64
    percentile::Float64
    percentile_iterated_to::Float64
end

value_iterated_to(iter::HistogramIterationValue) = iter.value_iterated_to
value_iterated_from(iter::HistogramIterationValue) = iter.value_iterated_from
count_at_value_iterated_to(iter::HistogramIterationValue) = iter.count_at_value_iterated_to
count_added_in_this_iteration_step(iter::HistogramIterationValue) = iter.count_added_in_this_iteration_step
total_count_to_this_value(iter::HistogramIterationValue) = iter.total_count_to_this_value
total_value_to_this_value(iter::HistogramIterationValue) = iter.total_value_to_this_value
percentile(iter::HistogramIterationValue) = iter.percentile
percentile_iterated_to(iter::HistogramIterationValue) = iter.percentile_iterated_to

@inline function has_next(iter::AbstractHistogramIterator, state::AbstractHistogramIteratorState)
    h = histogram(iter)
    if total_count(h) != total_count(state)
        error("Concurrent Modification Exception")
    end
    return total_count_to_current_index(state) < total_count(h)
end

function increment_iteration_level end
function reached_iteration_level end

function value_iterated_to(iter::AbstractHistogramIterator, state::AbstractHistogramIteratorState)
    h = histogram(iter)
    return highest_equivalent_value(h, current_value_at_index(state))
end

function increment_sub_bucket!(iter::AbstractHistogramIterator, state::AbstractHistogramIteratorState)
    h = histogram(iter)
    fresh_sub_bucket!(state, true)
    index = current_index(state) + 1
    current_index!(state, index)
    current_value_at_index!(state, value_at_index(h, index))
    next_value_at_index!(state, value_at_index(h, index + 1))
end

function Base.iterate(iter::AbstractHistogramIterator, state::AbstractHistogramIteratorState)
    h = histogram(iter)

    if total_count(h) != total_count(state)
        error("Concurrent Modification Exception")
    end
    while has_next(iter, state)
        count = count_at_index(h, current_index(state))
        count_at_this_value!(state, count)
        if fresh_sub_bucket(state)
            total_count_to_current_index!(state, total_count_to_current_index(state) + count)
            total_value_to_current_index!(state, total_value_to_current_index(state) + count * highest_equivalent_value(h, current_value_at_index(state)))
            fresh_sub_bucket!(state, false)
        end
        if reached_iteration_level(iter, state)
            val_iter_to = value_iterated_to(iter, state)

            current_iteration_value = HistogramIterationValue(
                val_iter_to,
                previous_value_iterated_to(state),
                count_at_this_value(state),
                total_count_to_current_index(state) - total_count_to_previous_index(state),
                total_count_to_current_index(state),
                total_value_to_current_index(state),
                100.0 * total_count_to_current_index(state) / total_count(state),
                percentile_iterated_to(iter, state))

            previous_value_iterated_to!(state, val_iter_to)
            total_count_to_previous_index!(state, total_count_to_current_index(state))

            increment_iteration_level!(iter, state)

            if total_count(h) != total_count(state)
                error("Concurrent Modification Exception")
            end

            return current_iteration_value, state
        end

        increment_sub_bucket!(iter, state)
    end

    if total_count_to_current_index(state) > total_count_to_previous_index(state)
        # We are at the end of the iteration but we still need to report
        # the last iteration value
        val_iter_to = value_iterated_to(iter, state)
        current_iteration_value = HistogramIterationValue(
            val_iter_to,
            previous_value_iterated_to(state),
            count_at_this_value(state),
            total_count_to_current_index(state) - total_count_to_previous_index(state),
            total_count_to_current_index(state),
            total_value_to_current_index(state),
            100.0 * total_count_to_current_index(state) / total_count(state),
            percentile_iterated_to(iter, state))
        # we do this one time only
        total_count_to_previous_index!(state, total_count_to_current_index(state))
        return current_iteration_value, state
    end

    return nothing
end

Base.eltype(::Type{<:AbstractHistogramIterator}) = HistogramIterationValue
Base.IteratorSize(::Type{<:AbstractHistogramIterator}) = Base.SizeUnknown()
Base.isdone(iter::AbstractHistogramIterator, state) = !has_next(iter, state)

function percentile_iterated_to(iter::AbstractHistogramIterator, state::AbstractHistogramIteratorState)
    return 100.0 * total_count_to_current_index(state) / total_count(histogram(iter))
end

function percentile_iterated_from(iter::AbstractHistogramIterator, state::AbstractHistogramIteratorState)
    return 100.0 * total_count_to_previous_index(state) / total_count(histogram(iter))
end