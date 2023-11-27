import ./config

when chronosProfiling:
  import futures
  import ./profiler/[events, metrics]

  export futures, events, metrics

  when not defined(chronosFutureId):
    {.error "chronosProfiling requires chronosFutureId to be enabled".}

  var futureMetrics {.threadvar.}: ProfilerMetrics 

  proc getMetrics*(): ProfilerMetrics = 
    ## Returns metrics for the current event loop.
    result = futureMetrics

  proc enableEventCallbacks*(): void =
    onFutureEvent = handleFutureEventCB
    onFutureExecEvent = handleFutureExecEventCB
    
  proc enable*() = 
    ## Enables profiling on the current event loop.
    if not isNil(handleFutureEvent): return

    enableEventCallbacks()
    handleFutureEvent = proc (e: Event) {.nimcall.} = 
      futureMetrics.processEvent(e)
