using Test

include("../src/HdrHistogram.jl")

using .HdrHistogram

const LOWEST = 1
const HIGHEST = 60 * 60 * 1000 * 1000 # e.g. for 1 hr in usec units
const SIGNIFICANT = 3
const TEST_VALUE_LEVEL = 4
const INTERVAL = 10_000
const SCALE = 512
const SCALED_INTERVAL = INTERVAL * SCALE

@testset "Basic" begin
    h = HdrHistogram.Histogram(Int64, LOWEST, HIGHEST, SIGNIFICANT)
    @test HdrHistogram.bucket_count(h) == 22
    @test HdrHistogram.sub_bucket_count(h) == 2048
    @test HdrHistogram.counts_length(h) == 23552
    @test HdrHistogram.unit_magnitude(h) == 0
    @test HdrHistogram.sub_bucket_half_count_magnitude(h) == 10
    @test HdrHistogram.counts_index(h, 0, 0) == 0
end

@testset "Empty" begin
    h = HdrHistogram.Histogram(Int64, LOWEST, HIGHEST, SIGNIFICANT)
    @test min(h) == typemax(Int64)
    @test max(h) == 0
    @test HdrHistogram.mean(h) == 0
    @test HdrHistogram.stddev(h) == 0
end

@testset "Large Numbers" begin
    h = HdrHistogram.Histogram(20_000_000, 100_000_000, 5)

    HdrHistogram.record_value!(h, 100_000_000)
    HdrHistogram.record_value!(h, 20_000_000)
    HdrHistogram.record_value!(h, 30_000_000)

    @test HdrHistogram.values_are_equivalent(h, 20_000_000, HdrHistogram.value_at_percentile(h, 50.0))
    @test HdrHistogram.values_are_equivalent(h, 30_000_000, HdrHistogram.value_at_percentile(h, 50.0))
    @test HdrHistogram.values_are_equivalent(h, 100_000_000, HdrHistogram.value_at_percentile(h, 83.33))
    @test HdrHistogram.values_are_equivalent(h, 100_000_000, HdrHistogram.value_at_percentile(h, 83.34))
    @test HdrHistogram.values_are_equivalent(h, 100_000_000, HdrHistogram.value_at_percentile(h, 99.0))
end

@testset "Recorded Values" begin
    h = HdrHistogram.Histogram(LOWEST, HIGHEST, SIGNIFICANT)
    HdrHistogram.record_value!(h, TEST_VALUE_LEVEL)
    @test HdrHistogram.count_at_value(h, TEST_VALUE_LEVEL) == 1
    @test HdrHistogram.total_count(h) == 1
end

@testset "Highest Equivalent Values" begin
    h = HdrHistogram.Histogram(LOWEST, HIGHEST, SIGNIFICANT)
    @test 8183 * 1024 + 1023 == HdrHistogram.highest_equivalent_value(h, 8180 * 1024)
    @test 8191 * 1024 + 1023 == HdrHistogram.highest_equivalent_value(h, 8191 * 1024)
    @test 8199 * 1024 + 1023 == HdrHistogram.highest_equivalent_value(h, 8193 * 1024)
    @test 9999 * 1024 + 1023 == HdrHistogram.highest_equivalent_value(h, 9995 * 1024)
    @test 10007 * 1024 + 1023 == HdrHistogram.highest_equivalent_value(h, 10007 * 1024)
    @test 10015 * 1024 + 1023 == HdrHistogram.highest_equivalent_value(h, 10008 * 1024)
end

@testset "Scaled Highest Equivalent Values" begin
    h = HdrHistogram.Histogram(LOWEST, HIGHEST, SIGNIFICANT)
    @test HdrHistogram.highest_equivalent_value(h, 8180) == 8183
    @test HdrHistogram.highest_equivalent_value(h, 8191) == 8191
    @test HdrHistogram.highest_equivalent_value(h, 8193) == 8199
    @test HdrHistogram.highest_equivalent_value(h, 9995) == 9999
    @test HdrHistogram.highest_equivalent_value(h, 10007) == 10007
    @test HdrHistogram.highest_equivalent_value(h, 10008) == 10015
end

@testset "Maximum and Minimum" begin
    h = HdrHistogram.Histogram(20000000, 100000000, 5)
    HdrHistogram.record_value!(h, 100000000)
    HdrHistogram.record_value!(h, 20000000)
    HdrHistogram.record_value!(h, 30000000)
    @test HdrHistogram.max_value(h) == 100000000
    @test HdrHistogram.min_value(h) == 20000000
end

@testset "Get value at percentile" begin
    h = HdrHistogram.Histogram(LOWEST, 3600000000, 3)
    HdrHistogram.record_value!(h, 1)
    HdrHistogram.record_value!(h, 2)
    @test HdrHistogram.value_at_percentile(h, 50.0) == 1
    @test HdrHistogram.value_at_percentile(h, 50.00000000000001) == 1
    HdrHistogram.record_value!(h, 2)
    HdrHistogram.record_value!(h, 2)
    HdrHistogram.record_value!(h, 2)
    @test HdrHistogram.value_at_percentile(h, 30.0) == 2
end

@testset "Mean and Standard Deviation" begin
    h = HdrHistogram.Histogram(LOWEST, HIGHEST, SIGNIFICANT)
    val = [1000, 1000, 3000, 3000]
    for v in val
        HdrHistogram.record_value!(h, v)
    end
    @test HdrHistogram.mean(h) == 2000.5
    @test HdrHistogram.stddev(h) == 1000.5
end

function load_histogram()
    h = HdrHistogram.Histogram(LOWEST, HIGHEST, SIGNIFICANT)
    HdrHistogram.record_value!(h, 1000, 10_000)
    HdrHistogram.record_value!(h, 100_000_000)
    return h
end

function load_corrected_histogram()
    h = HdrHistogram.Histogram(LOWEST, HIGHEST, SIGNIFICANT)
    HdrHistogram.record_corrected_value!(h, 1000, INTERVAL, 10_000)
    HdrHistogram.record_corrected_value!(h, 100_000_000, INTERVAL)
    return h
end

function load_scaled_histogram()
    h = HdrHistogram.Histogram(1000, HIGHEST * SCALE, SIGNIFICANT)
    HdrHistogram.record_value!(h, 1000 * SCALE, 10_000)
    HdrHistogram.record_value!(h, 100_000_000 * SCALE)
    return h
end

function load_scaled_corrected_histogram()
    h = HdrHistogram.Histogram(1000, HIGHEST * SCALE, SIGNIFICANT)
    HdrHistogram.record_corrected_value!(h, 1000 * SCALE, SCALED_INTERVAL, 10_000)
    HdrHistogram.record_corrected_value!(h, 100_000_000 * SCALE, SCALED_INTERVAL)
    return h
end

@testset "Total count" begin
    h = load_histogram()
    @test HdrHistogram.total_count(h) == 10001
    h = load_corrected_histogram()
    @test HdrHistogram.total_count(h) == 20000
end

@testset "Out of range" begin
    h = HdrHistogram.Histogram(1, 1000, 4)
    # @test HdrHistogram.record_value!(h, 32767)
    @test_throws ArgumentError HdrHistogram.record_value!(h, -1)
    @test_throws ArgumentError HdrHistogram.record_value!(h, 32767, 0)
    @test_throws ArgumentError HdrHistogram.record_value!(h, 32768)
end

@testset "Recorded Values Iterator" begin
    h = load_histogram()
    index = 0
    for i in HdrHistogram.RecordedValuesIterator(h)
        count_added_in_this_iteration = HdrHistogram.count_added_in_this_iteration_step(i)
        if index == 0
            @test count_added_in_this_iteration == 10000
        else
            @test count_added_in_this_iteration == 1
        end
        index += 1
    end
    @test index == 2

    h = load_corrected_histogram()
    index = 0
    total_added_count = 0
    for i in HdrHistogram.RecordedValuesIterator(h)
        count_added_in_this_iteration = HdrHistogram.count_added_in_this_iteration_step(i)
        if index == 0
            @test count_added_in_this_iteration == 10000
        end
        @test HdrHistogram.count_at_value_iterated_to(i) != 0
        @test HdrHistogram.count_at_value_iterated_to(i) == count_added_in_this_iteration
        total_added_count += count_added_in_this_iteration
        index += 1
    end
    @test total_added_count == 20000
    @test total_added_count == HdrHistogram.total_count(h)
end

# This test is from the C implementation which allows concurrent modification
# @testset "Linear Iterator Buckets" begin
#     step_count = 0
#     total_count = 0
#     h = HdrHistogram.Histogram(1, 255, 2)
#     vals = [193, 255, 0, 1, 64, 128]
#     for i in vals
#         HdrHistogram.record_value!(h, i)
#     end

#     for i in HdrHistogram.LinearIterator(h, 64)
#         total_count += HdrHistogram.count_added_in_this_iteration_step(i)
#         if step_count == 0
#             HdrHistogram.record_value!(h, 2)
#         end
#         step_count += 1
#     end

#     @test step_count == 4
#     @test total_count == 6
# end

@testset "Linear Values Iterator" begin
    h = load_histogram()
    index = 0
    for i in HdrHistogram.LinearIterator(h, 100_000)
        count_added_in_this_iteration = HdrHistogram.count_added_in_this_iteration_step(i)
        if index == 0
            @test count_added_in_this_iteration == 10000
        elseif index == 999
            @test count_added_in_this_iteration == 1
        else
            @test count_added_in_this_iteration == 0
        end
        index += 1
    end
    @test index == 1000

    h = load_corrected_histogram()
    index = 0
    total_added_count = 0
    for i in HdrHistogram.LinearIterator(h, 10_000)
        count_added_in_this_iteration = HdrHistogram.count_added_in_this_iteration_step(i)
        if index == 0
            # first bucket is range [0, 10000]
            # value 1000  count = 10000
            # value 10000 count = 1 (corrected from the 100M value with 10K interval)
            @test count_added_in_this_iteration == 10_001
        end
        total_added_count += count_added_in_this_iteration
        index += 1
    end
    @test index == 10000
    @test total_added_count == 20000
end

@testset "Logarithmic Values Iterator" begin
    h = load_histogram()
    index = 0
    for i in HdrHistogram.LogarithmicIterator(h, 10_000, 2.0)
        count_added_in_this_iteration = HdrHistogram.count_added_in_this_iteration_step(i)
        if index == 0
            @test count_added_in_this_iteration == 10000
        elseif index == 14
            @test count_added_in_this_iteration == 1
        else
            @test count_added_in_this_iteration == 0
        end
        index += 1
    end
    @test index == 15

    h = load_corrected_histogram()
    index = 0
    total_added_count = 0
    for i in HdrHistogram.LogarithmicIterator(h, 10_000, 2.0)
        count_added_in_this_iteration = HdrHistogram.count_added_in_this_iteration_step(i)
        if index == 0
            # first bucket is range [0, 10000]
            # value 1000  count = 10000
            # value 10000 count = 1 (corrected from the 100M value with 10K interval)
            @test count_added_in_this_iteration == 10_001
        end
        total_added_count += count_added_in_this_iteration
        index += 1
    end
    @test index == 15
    @test total_added_count == 20000
end

function compare_values(a, b, ϵ)
    @test abs(a - b) <= (b * ϵ)
end

@testset "Check percentiles" begin
    h = load_histogram()
    compare_values(HdrHistogram.value_at_percentile(h, 30.0), 1000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 99.0), 1000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 99.99), 1000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 99.999), 100000000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 100.0), 100000000, 0.001)

    h = load_corrected_histogram()
    compare_values(HdrHistogram.value_at_percentile(h, 30.0), 1000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 50.0), 1000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 75.0), 50000000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 90.0), 80000000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 99.0), 98000000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 99.999), 100000000, 0.001)
    compare_values(HdrHistogram.value_at_percentile(h, 100.0), 100000000, 0.001)

    percentiles = [30.0, 99.0, 99.99, 99.999, 100.0]
    vals = zeros(Int64, length(percentiles))
    HdrHistogram.value_at_percentile(h, percentiles, vals)
    for (p, v) in zip(percentiles, vals)
        compare_values(HdrHistogram.value_at_percentile(h, p), v, 0.001)
    end
end

@testset "Percentile Iterator" begin
    h = load_histogram()
    for i in HdrHistogram.PercentileIterator(h, 5)
        expected = HdrHistogram.highest_equivalent_value(h, HdrHistogram.value_at_percentile(h, HdrHistogram.percentile(i)))
        @test HdrHistogram.value_iterated_to(i) == expected
    end
end

@testset "Test scaling equivalence" begin
    h1 = load_corrected_histogram()
    h2 = load_scaled_corrected_histogram()

    compare_values(HdrHistogram.mean(h1) * SCALE,
        HdrHistogram.mean(h2),
        0.000001)
    compare_values(HdrHistogram.total_count(h1),
        HdrHistogram.total_count(h2),
        0)

    expected_99th = HdrHistogram.value_at_percentile(h1, 99.0) * SCALE
    scaled_99th = HdrHistogram.value_at_percentile(h2, 99.0)

    compare_values(HdrHistogram.lowest_equivalent_value(h1, expected_99th),
        HdrHistogram.lowest_equivalent_value(h2, scaled_99th),
        0)
end