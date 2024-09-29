mutable struct IntervalRecorder{T<:AbstractHistogram}
    const phaser::WriterReaderPhaser
    @atomic active::T
    function IntervalRecorder(histogram::T) where {T}
        new{T}(
            WriterReaderPhaser(),
            histogram
        )
    end
end

function record_value!(r::IntervalRecorder, value::Int64, count::Int64=1)
    val = writer_critical_section_enter(r.phaser)
    try
        record_value!((@atomic r.active), value, count)
    finally
        writer_critical_section_exit(r.phaser, val)
    end
end

function record_corrected_value!(r::IntervalRecorder, value::Int64, expected_interval::Int64, count::Int64=1)
    val = writer_critical_section_enter(r.phaser)
    try
        record_corrected_value!((@atomic r.active), value, expected_interval, count)
    finally
        writer_critical_section_exit(r.phaser, val)
    end
end

function interval_histogram(r::IntervalRecorder)
    reader_lock(r.phaser)
    inactive = @atomicswap r.active = copy(r.active)
    flip_phase(r.phaser)
    reader_unlock(r.phaser)

    return inactive
end

function interval_histogram(r::IntervalRecorder{T}, inactive::T) where {T<:AbstractHistogram}
    reset!(inactive)

    reader_lock(r.phaser)
    inactive = @atomicswap r.active = inactive
    flip_phase(r.phaser)
    reader_unlock(r.phaser)

    return inactive
end
