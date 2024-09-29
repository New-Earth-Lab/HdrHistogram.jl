mutable struct WriterReaderPhaser
    @atomic start_epoch::Int64
    @atomic even_end_epoch::Int64
    @atomic odd_end_epoch::Int64
    const reader_lock::ReentrantLock

    function WriterReaderPhaser()
        new(0, 0, typemin(Int64), ReentrantLock())
    end
end

@inline function writer_critical_section_enter(phaser::WriterReaderPhaser)
    (@atomic phaser.start_epoch += 1) - 1
end

@inline function writer_critical_section_exit(phaser::WriterReaderPhaser, critical_value_at_enter)
    if critical_value_at_enter < 0
        @atomic phaser.odd_end_epoch += 1
    else
        @atomic phaser.even_end_epoch += 1
    end
end

reader_lock(phaser::WriterReaderPhaser) = lock(phaser.reader_lock)
reader_unlock(phaser::WriterReaderPhaser) = unlock(phaser.reader_lock)

@inline function flip_phase(phaser::WriterReaderPhaser, yield_time_nsec::Int64=0)
    Base.assert_havelock(phaser.reader_lock)
    
    next_phase_is_even = (@atomic phaser.start_epoch) < 0

    initial_start_value = next_phase_is_even ? 0 : typemin(Int64)
    if next_phase_is_even
        @atomic phaser.even_end_epoch = initial_start_value
    else
        @atomic phaser.odd_end_epoch = initial_start_value
    end

    start_value_at_flip = @atomicswap phaser.start_epoch = initial_start_value

    while (next_phase_is_even ? (@atomic phaser.odd_end_epoch) : (@atomic phaser.even_end_epoch)) != start_value_at_flip
        if yield_time_nsec == 0
            yield()
        else
            sleep(yield_time_nsec / 1e9)
        end
    end
end