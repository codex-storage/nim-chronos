import ./config

when chronosProfiling:
  import ./futures
  import ./profiler/metrics

  export futures, metrics

  when not chronosFutureId:
    {.error: "chronosProfiling requires chronosFutureId to be enabled".}

  proc getMetrics*(): ProfilerMetrics = 
    ## Returns metrics for the current event loop.
    result = metrics.getMetrics()

  proc enableProfiling*() =
    ## Enables profiling on the current event loop.
    onFutureEvent = metrics.handleFutureEvent
