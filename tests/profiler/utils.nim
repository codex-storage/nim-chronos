import std/sequtils
import std/sugar

import ".."/".."/chronos
import ".."/".."/chronos/profiler/events

type
  SimpleEvent* = object
    procedure*: string
    state*: ExtendedFutureState

# XXX this is sort of bad cause we get global state all over, but the fact we
#   can't use closures on callbacks and that callbacks themselves are just
#   global vars means we can't really do much better for now.

var recording: seq[SimpleEvent]

proc forProcs*(self: seq[SimpleEvent], procs: varargs[string]): seq[SimpleEvent] =
  collect:
    for e in self:
      if e.procedure in procs:
        e

# FIXME bad, this needs to be refactored into a callback interface for the profiler.
var oldHandleFutureEvent: proc(event: Event) {.nimcall, gcsafe, raises: [].} = nil
var installed: bool = false

proc recordEvent(event: Event) {.nimcall, gcsafe, raises: [].} =
  {.cast(gcsafe).}:
    recording.add(
      SimpleEvent(
        procedure: $(event.location.procedure),
        state: event.newState
      )
    )

proc getRecording*(): seq[SimpleEvent] = {.cast(gcsafe).}: recording

proc clearRecording*(): void = recording = @[]

proc installCallbacks*() =
  assert not installed, "Callbacks already installed"
  oldHandleFutureEvent = handleFutureEvent
  handleFutureEvent = recordEvent

  installed = true

proc revertCallbacks*() =
  assert installed, "Callbacks already uninstalled"
  
  handleFutureEvent = oldHandleFutureEvent
  installed = false

