import std/os

import unittest2

import ".."/".."/chronos
import ".."/".."/chronos/profiler/events

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

    check getRecording().forProcs("simple") == @[
      SimpleEvent(state: Pending, procedure: "simple"),
      SimpleEvent(state: ExtendedFutureState.Running, procedure: "simple"),
      SimpleEvent(state: Completed, procedure: "simple"),
    ]

  # test "should emit correct events for a future with children":
  #   proc child1() {.async.} =
  #     os.sleep(1)

  #   proc withChildren() {.async.} =
  #     await child1()

  #   waitFor withChildren()

  #   check getRecording().forProcs("withChildren", "child1") == @[
  #     Event(kind: EventKind.Create, procedure: "withChildren"),
  #     Event(kind: EventKind.Run, procedure: "withChildren"),
  #     Event(kind: EventKind.Create, procedure: "child1"),
  #     Event(kind: EventKind.Pause, procedure: "withChildren"),
  #     Event(kind: EventKind.Run, procedure: "child1"),
  #     Event(kind: EventKind.Complete, procedure: "child1"),
  #     Event(kind: EventKind.Run, procedure: "withChildren"),
  #     Event(kind: EventKind.Complete, procedure: "withChildren"),
  #   ]

  # test "should emit correct events for a future with timers":
  #   proc withChildren() {.async.} =
  #     await sleepAsync(1.milliseconds)

  #   waitFor withChildren()

  #   check getRecording().forProcs(
  #       "withChildren", "chronos.sleepAsync(Duration)") == @[
  #     Event(kind: EventKind.Create, procedure: "withChildren"),
  #     Event(kind: EventKind.Run, procedure: "withChildren"),
  #     Event(kind: EventKind.Pause, procedure: "withChildren"),
  #     Event(kind: EventKind.Create, procedure: "chronos.sleepAsync(Duration)"),
  #     # Timers don't "run"
  #     Event(kind: EventKind.Complete, procedure: "chronos.sleepAsync(Duration)"),
  #     Event(kind: EventKind.Run, procedure: "withChildren"),
  #     Event(kind: EventKind.Complete, procedure: "withChildren"),
  #   ]

  # test "should emit correct events when futures are canceled":
  #   proc withCancellation() {.async.} =
  #     let f = sleepyHead()
  #     f.cancel()

  #   proc sleepyHead() {.async.} =
  #     await sleepAsync(10.minutes)

  #   waitFor withCancellation()

  #   check getRecording().forProcs("sleepyHead", "withCancellation") == @[
  #     Event(kind: EventKind.Create, procedure: "withCancellation"),
  #     Event(kind: EventKind.Create, procedure: "sleepyHead"),
  #     Event(kind: EventKind.Run, procedure: "sleepyHead"),
  #   ]

# type
#   FakeFuture = object
#     id: uint
#     internalLocation*: array[LocationKind, ptr SrcLoc]

# suite "asyncprofiler metrics":

#   test "should not keep metrics for a pending future in memory after it completes":

#     var fakeLoc =  SrcLoc(procedure: "foo", file: "foo.nim", line: 1)
#     let future = FakeFuture(
#       id: 1,
#       internalLocation:  [
#       LocationKind.Create: addr fakeLoc,
#       LocationKind.Finish: addr fakeLoc,
#     ])

#     var profiler = AsyncProfiler[FakeFuture]()

#     profiler.handleFutureCreate(future)
#     profiler.handleFutureComplete(future)

#     check len(profiler.getPerFutureMetrics()) == 0

