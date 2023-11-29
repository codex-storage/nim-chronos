import ./config

when chronosProfiling:
  import futures
  import ./profiler/[events, metrics]

  export futures, events, metrics

  when not chronosFutureId:
    {.error: "chronosProfiling requires chronosFutureId to be enabled".}

  var futureMetrics {.threadvar.}: ProfilerMetrics 

  proc getMetrics*(): ProfilerMetrics = 
    ## Returns metrics for the current event loop.
    result = futureMetrics

  proc setFutureEventCallback*(): void =

  proc enableProfiling*() =
    ## Enables profiling on the current event loop.
    onFutureEvent = metrics.handleFutureEvent
