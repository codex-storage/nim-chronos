import ".."/timer
import ".."/futures
import ".."/srcloc

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
  
onFutureEvent = proc (future: FutureBase, state: FutureState): void {.nimcall.} =
  {.cast(gcsafe).}:
    let extendedState = case state:
      of FutureState.Pending: ExtendedFutureState.Pending
      of FutureState.Completed: ExtendedFutureState.Completed
      of FutureState.Cancelled: ExtendedFutureState.Cancelled
      of FutureState.Failed: ExtendedFutureState.Failed

    if not isNil(handleFutureEvent):
      handleFutureEvent(mkEvent(future, extendedState))

onFutureExecEvent = proc (future: FutureBase, state: FutureExecutionState): void {.nimcall.} =
  {.cast(gcsafe).}:
    let extendedState = case state:
      of FutureExecutionState.Running: ExtendedFutureState.Running
      of FutureExecutionState.Paused: ExtendedFutureState.Paused

    if not isNil(handleFutureEvent):
      handleFutureEvent(mkEvent(future, extendedState))



