HdrHistogram.jl: Julia port of High Dynamic Range (HDR) Histogram

HdrHistogram
----------------------------------------------

This port contains a subset of the functionality supported by the Java
implementation.  The current supported features are:

* Standard histogram with parametric count size (64 bit counts default)
* Atomic histograms
* All iterator types (all values, recorded, percentiles, linear, logarithmic)
* Auto-resizing of histograms

Features not supported, but planned:

* Histogram serialisation (encoding version 1.2, decoding 1.0-1.2)
* Reader/writer phaser and interval recorder

Features unlikely to be implemented:

* Double histograms
* Concurrent histograms

# Simple Tutorial

## Recording values

```Julia
using HdrHistogram

# Initialise the histogram
histogram = HdrHistogram.Histogram(
    1,          # Minimum value
    3600000000, # Maximum value
    3           # Number of significant figures
)

# Record value
HdrHistogram.record_value!(
    histogram,      # Histogram to record to
    value)          # Value to record

# Record value n times
HdrHistogram.record_value!(
    histogram,      # Histogram to record to
    value,          # Value to record
    10)             # Record value 10 times

# Record value with correction for co-ordinated omission.
HdrHistogram.record_corrected_value!(
    histogram,      # Histogram to record to
    value,          # Value to record
    1000)           # Record with expected interval of 1000.

# Print out the values of the histogram
HdrHistogram.percentiles_print(
    stdout,         # IO to write to
    histogram,      # Histogram to print
    5,              # Granularity of printed values
    1.0)            # Multiplier for results
```