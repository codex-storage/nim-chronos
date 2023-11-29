import std/os

import unittest2

import ".."/".."/chronos
import ".."/".."/chronos/profiler

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
      recordSegment("segment 21")
      await sleepAsync(10.milliseconds)
      recordSegment("segment 22")
      await sleepAsync(10.milliseconds)
      recordSegment("segment 23")

    proc child1() {.async.} =
      recordSegment("segment 11")
      await child2()
      recordSegment("segment 12")

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
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "segment 11"),
      SimpleEvent(state: ExtendedFutureState.Pending, procedure: "child2"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "child2"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "segment 21"),
      SimpleEvent(state: ExtendedFutureState.Pending, procedure: "chronos.sleepAsync(Duration)"),
      SimpleEvent(state: ExtendedFutureState.Paused, procedure: "child2"),
      SimpleEvent(state: ExtendedFutureState.Paused, procedure: "child1"),
      SimpleEvent(state: ExtendedFutureState.Paused, procedure: "withChildren"),

      # Second iteration of child2
      SimpleEvent(state: ExtendedFutureState.Completed, procedure: "chronos.sleepAsync(Duration)"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "child2"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "segment 22"),
      SimpleEvent(state: ExtendedFutureState.Pending, procedure: "chronos.sleepAsync(Duration)"),
      SimpleEvent(state: ExtendedFutureState.Paused, procedure: "child2"),
      SimpleEvent(state: ExtendedFutureState.Completed, procedure: "chronos.sleepAsync(Duration)"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "child2"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "segment 23"),
      SimpleEvent(state: ExtendedFutureState.Completed, procedure: "child2"),

      # Second iteration child1
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "child1"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "segment 12"),
      SimpleEvent(state: ExtendedFutureState.Completed, procedure: "child1"),

      # Second iteration of parent
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "withChildren"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "segment 2"),
      SimpleEvent(state: ExtendedFutureState.Completed, procedure: "withChildren"),
    ]

  test "should not say a future is completed before children in finally blocks are run":
    skip()
    when false:
      # TODO: chronos allows completed futures to generate children in their
      #   finally blocks. This causes a set of transitions that break our state
      #   machine.
      proc withFinally(): Future[void] {.async.} =
        try:
          return
        finally:
          await sleepAsync(10.milliseconds)

      waitFor withFinally()

      check recording == @[
        SimpleEvent(state: Pending, procedure: "withFinally"),
        SimpleEvent(state: ExtendedFutureState.Running, procedure: "withFinally"),
        SimpleEvent(state: ExtendedFutureState.Pending, procedure: "chronos.sleepAsync(Duration)"),
        SimpleEvent(state: ExtendedFutureState.Paused, procedure: "withFinally"),
        SimpleEvent(state: ExtendedFutureState.Completed, procedure: "chronos.sleepAsync(Duration)"),
        SimpleEvent(state: ExtendedFutureState.Running, procedure: "withFinally"),
        SimpleEvent(state: ExtendedFutureState.Completed, procedure: "withFinally")
      ]
