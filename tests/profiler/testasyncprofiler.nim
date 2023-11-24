import std/os

import unittest2

import ".."/".."/chronos
import ".."/".."/chronos/profiler/[events, metrics]

import ./utils

suite "profiler hooks test suite":

  setup:
    installCallbacks()

  teardown:
    clearRecording()
    revertCallbacks()

  test "should emit correct events for a simple future":
    
    proc simple() {.async.} =
      os.sleep(1)
      
    waitFor simple()

    check recording == @[
      SimpleEvent(state: Pending, procedure: "simple"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "simple"),
      SimpleEvent(state: Completed, procedure: "simple"),
    ]

  test "should emit correct events when a single child runs as part of the parent":

    proc withChildren() {.async.} =
      recordSegment("segment 1")
      await sleepAsync(10.milliseconds)
      recordSegment("segment 2")
      
    waitFor withChildren()


    check recording == @[
      SimpleEvent(state: Pending, procedure: "withChildren"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "withChildren"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "segment 1"),
      SimpleEvent(state: ExtendedFutureState.Pending, procedure: "chronos.sleepAsync(Duration)"),
      SimpleEvent(state: Paused, procedure: "withChildren"),
      SimpleEvent(state: Completed, procedure: "chronos.sleepAsync(Duration)"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "withChildren"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "segment 2"),
      SimpleEvent(state: Completed, procedure: "withChildren"),
    ]

  test "should emit correct events when a nested child pauses execution":
    proc child2() {.async.} =
      await sleepAsync(10.milliseconds)
      await sleepAsync(10.milliseconds)

    proc child1() {.async.} =
      await child2()

    proc withChildren() {.async.} =
      recordSegment("segment 1")
      await child1()
      recordSegment("segment 2")
            
    waitFor withChildren()

    check recording == @[
      # First iteration of parent and each child
      SimpleEvent(state: Pending, procedure: "withChildren"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "withChildren"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "segment 1"),
      SimpleEvent(state: ExtendedFutureState.Pending, procedure: "child1"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "child1"),
      SimpleEvent(state: ExtendedFutureState.Pending, procedure: "child2"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "child2"),
      SimpleEvent(state: ExtendedFutureState.Pending, procedure: "chronos.sleepAsync(Duration)"),
      SimpleEvent(state: ExtendedFutureState.Paused, procedure: "child2"),
      SimpleEvent(state: ExtendedFutureState.Paused, procedure: "child1"),
      SimpleEvent(state: ExtendedFutureState.Paused, procedure: "withChildren"),

      # Second iteration of child2
      SimpleEvent(state: ExtendedFutureState.Completed, procedure: "chronos.sleepAsync(Duration)"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "child2"),
      SimpleEvent(state: ExtendedFutureState.Pending, procedure: "chronos.sleepAsync(Duration)"),
      SimpleEvent(state: ExtendedFutureState.Paused, procedure: "child2"),
      SimpleEvent(state: ExtendedFutureState.Completed, procedure: "chronos.sleepAsync(Duration)"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "child2"),
      SimpleEvent(state: ExtendedFutureState.Completed, procedure: "child2"),

      # Second iteration child1
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "child1"),
      SimpleEvent(state: ExtendedFutureState.Completed, procedure: "child1"),

      # Second iteration of parent
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "withChildren"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "segment 2"),
      SimpleEvent(state: ExtendedFutureState.Completed, procedure: "withChildren"),
    ]


suite "profiler metrics test suite":
  
    setup:
      installCallbacks()

    teardown:
      clearRecording()
      revertCallbacks()
      resetTime()
  
    test "should compute correct times for a simple future":

      var metrics = ProfilerMetrics()

      proc simple() {.async.} =
        advanceTime(50.milliseconds)
        
      waitFor simple()

      metrics.processAllEvents(rawRecording)

      let simpleMetrics = metrics.forProc("simple")
      
      check simpleMetrics.execTime == 50.milliseconds
      check simpleMetrics.wallClockTime == 50.milliseconds


    # test "should compute correct times when a single child runs as part of the parent":

    #   var metrics = ProfilerMetrics()

    #   proc child1() {.async.} = 
    #     advanceTime(10.milliseconds)

    #   proc withChildren() {.async.} =
    #     advanceTime(10.milliseconds)
    #     await child1()
    #     advanceTime(10.milliseconds)
        
    #   waitFor withChildren()

    #   metrics.processAllEvents(rawRecording)
     
    #   let withChildrenMetrics = metrics.forProc("withChildren")
    #   let child1Metrics = metrics.forProc("child1")

    #   check withChildrenMetrics.execTime == 20.milliseconds
    #   check withChildrenMetrics.childrenExecTime == 10.milliseconds
    #   check withChildrenMetrics.wallClockTime == 30.milliseconds

    #   check child1Metrics.execTime == 10.milliseconds
    #   check child1Metrics.wallClockTime == 10.milliseconds 
  
#     # test "should emit correct metrics when a single child runs as part of the parent":
  
#     #   proc withChildren() {.async.} =
#     #     recordSegment("segment 1")
#     #     await sleepAsync(10.milliseconds)
#     #     recordSegment("segment 2")
        
#     #   waitFor withChildren()