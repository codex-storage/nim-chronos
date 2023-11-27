import unittest2

import ".."/".."/chronos
import ".."/".."/chronos/profiler/metrics

import ./utils

suite "profiler metrics test suite":
  
    setup:
      installCallbacks()

    teardown:
      clearRecording()
      revertCallbacks()
      resetTime()

    proc recordedMetrics(): ProfilerMetrics = 
      result.processAllEvents(rawRecording)
  
    test "should compute correct times for a simple blocking future":
      proc simple() {.async.} =
        advanceTime(50.milliseconds)
        
      waitFor simple()

      var metrics = recordedMetrics()
      let simpleMetrics = metrics.forProc("simple")
      
      check simpleMetrics.execTime == 50.milliseconds
      check simpleMetrics.wallClockTime == 50.milliseconds

    test "should compute correct times for a simple non-blocking future":
      proc simple {.async.} =
        advanceTime(10.milliseconds)
        await advanceTimeAsync(50.milliseconds)
        advanceTime(10.milliseconds)

      waitFor simple()

      var metrics = recordedMetrics()
      let simpleMetrics = metrics.forProc("simple")

      check simpleMetrics.execTime == 20.milliseconds
      check simpleMetrics.wallClockTime == 70.milliseconds

    test "should compute correct times whent there is a single blocking child":
      proc child() {.async.} = 
        advanceTime(10.milliseconds)

      proc parent() {.async.} =
        advanceTime(10.milliseconds)
        await child()
        advanceTime(10.milliseconds)
        
      waitFor parent()

      var metrics = recordedMetrics()
      let parentMetrics = metrics.forProc("parent")
      let childMetrics = metrics.forProc("child")

      check parentMetrics.execTime == 20.milliseconds
      check parentMetrics.childrenExecTime == 10.milliseconds
      check parentMetrics.wallClockTime == 30.milliseconds

      check childMetrics.execTime == 10.milliseconds
      check childMetrics.wallClockTime == 10.milliseconds
