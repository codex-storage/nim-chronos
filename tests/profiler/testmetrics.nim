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
  
    test "should compute correct times for a simple future":
      proc simple() {.async.} =
        advanceTime(50.milliseconds)
        
      waitFor simple()

      var metrics = ProfilerMetrics()
      metrics.processAllEvents(rawRecording)
      let simpleMetrics = metrics.forProc("simple")
      
      check simpleMetrics.execTime == 50.milliseconds
      check simpleMetrics.wallClockTime == 50.milliseconds

    test "should compute correct times for blocking children":
      proc child() {.async.} = 
        advanceTime(10.milliseconds)

      proc parent() {.async.} =
        advanceTime(10.milliseconds)
        await child()
        advanceTime(10.milliseconds)
        
      waitFor parent()

      var metrics = ProfilerMetrics()
      metrics.processAllEvents(rawRecording)
      let parentMetrics = metrics.forProc("parent")
      let childMetrics = metrics.forProc("child")

      check parentMetrics.execTime == 20.milliseconds
      check parentMetrics.childrenExecTime == 10.milliseconds
      check parentMetrics.wallClockTime == 30.milliseconds

      check childMetrics.execTime == 10.milliseconds
      check childMetrics.wallClockTime == 10.milliseconds
