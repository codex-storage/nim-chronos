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
    futureId*: uint
    location*: SrcLoc
    newState*: ExtendedFutureState
  
  RunningFuture = object
    event: Event
    notNil: bool
    
var running* {.threadvar.}: RunningFuture
var handleFutureEvent* {.threadvar.}: proc (event: Event) {.nimcall, gcsafe, raises: [].}

proc dispatch(future: FutureBase, state: ExtendedFutureState) =
  let event = Event(
    futureId: future.id,
    location: future.internalLocation[LocationKind.Create][], 
    newState: state
  )

  if state != ExtendedFutureState.Running:
    handleFutureEvent(event)
    return

  # If we have a running future, then it means this is a child. Emits synthetic
  # pause event to keep things consistent with thread occupancy semantics.
  if running.notNil:
    handleFutureEvent(Event(
      futureId: running.event.futureId, 
      location: running.event.location, 
      newState: Paused
    ))

  running = RunningFuture(event: event, notNil: true)
  
  handleFutureEvent(event)

onFutureEvent = proc (future: FutureBase, state: FutureState): void {.nimcall.} =
  {.cast(gcsafe).}:
    let extendedState = case state:
      of FutureState.Pending: ExtendedFutureState.Pending
      of FutureState.Completed: ExtendedFutureState.Completed
      of FutureState.Cancelled: ExtendedFutureState.Cancelled
      of FutureState.Failed: ExtendedFutureState.Failed

    dispatch(future, extendedState)

onFutureExecEvent = proc (future: FutureBase, state: FutureExecutionState): void {.nimcall.} =
  {.cast(gcsafe).}:
    let extendedState = case state:
      of FutureExecutionState.Running: ExtendedFutureState.Running
      of FutureExecutionState.Paused: ExtendedFutureState.Paused

    dispatch(future, extendedState)



