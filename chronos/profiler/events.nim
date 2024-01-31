## This module defines the lower-level callback implementations that hook into
## the Chronos scheduler when profiling is enabled. The main goal is to provide
## timestamped state changes for futures, which form the input for the profiler.

import ../timer
import ../futures
import ../srcloc

type
  ExtendedFutureState* {.pure.} = enum
    Pending,
    Running,
    Paused,
    Completed,
    Cancelled,
    Failed,

  Event* = object
    future: FutureBase
    newState*: ExtendedFutureState
    timestamp*: Moment
  
var handleFutureEvent* {.threadvar.}: proc (event: Event) {.nimcall, gcsafe, raises: [].}

proc `location`*(self: Event): SrcLoc =
  self.future.internalLocation[Create][]

proc `futureId`*(self: Event): uint =
  self.future.id

proc mkEvent(future: FutureBase, state: ExtendedFutureState): Event =
  Event(
    future: future,
    newState: state,
    timestamp: Moment.now(),
  )
  
proc handleBaseFutureEvent*(future: FutureBase,
    state: FutureState): void {.nimcall.} =
  {.cast(gcsafe).}:
    let extendedState = case state:
      of FutureState.Pending: ExtendedFutureState.Pending
      of FutureState.Completed: ExtendedFutureState.Completed
      of FutureState.Cancelled: ExtendedFutureState.Cancelled
      of FutureState.Failed: ExtendedFutureState.Failed

    if not isNil(handleFutureEvent):
      handleFutureEvent(mkEvent(future, extendedState))

proc handleAsyncFutureEvent*(future: FutureBase,
    state: AsyncFutureState): void {.nimcall.} =
  {.cast(gcsafe).}:
    let extendedState = case state:
      of AsyncFutureState.Running: ExtendedFutureState.Running
      of AsyncFutureState.Paused: ExtendedFutureState.Paused

    if not isNil(handleFutureEvent):
      handleFutureEvent(mkEvent(future, extendedState))



