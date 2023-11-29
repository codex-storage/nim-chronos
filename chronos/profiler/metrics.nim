import std/tables
import std/options

import ./events
import ../[timer, srcloc]

export timer, tables, srcloc

type
  Event* = object
    futureId: uint
    loc: SrcLoc
    state: FutureState
    event*: FutureExecutionEvent
    timestamp*: Moment

proc processEvent*(self: var ProfilerMetrics, event: Event): void

proc handleFutureEvent*(future: FutureBase,
                        event: FutureExecutionEvent): void {.nimcall.} =
  {.cast(gcsafe).}:
    let extendedState = case state:
        of Init: ExtendedFutureState.Pending
        of Run: ExtendedFutureState.Running
        of Pause: ExtendedFutureState.Paused
        of Finish: future.internalState.toExtendedEvent()

    processEvent Event(
        future: future,
        loc: future.internalLocation[Create][],
        state: future.internalState,
        event: event,
        timestamp: Moment.now()
    )

type
  AggregateFutureMetrics* = object
    execTime*: Duration
    execTimeMax*: Duration
    childrenExecTime*: Duration
    wallClockTime*: Duration
    callCount*: uint

  RunningFuture* = object
    state*: ExtendedFutureState
    created*: Moment
    lastStarted*: Moment
    timeToFirstPause*: Duration
    partialExecTime*: Duration
    partialChildrenExecTime*: Duration
    partialChildrenExecOverlap*: Duration
    parent*: Option[uint]
    pauses*: uint

  MetricsTotals* = Table[SrcLoc, AggregateFutureMetrics]

  ProfilerMetrics* = object
    callStack: seq[uint]
    partials: Table[uint, RunningFuture]
    totals*: MetricsTotals

proc `execTimeWithChildren`*(self: AggregateFutureMetrics): Duration =
  self.execTime + self.childrenExecTime

proc push(self: var seq[uint], value: uint): void = self.add(value)

proc pop(self: var seq[uint]): uint =
  let value = self[^1]
  self.setLen(self.len - 1)
  value

proc peek(self: var seq[uint]): Option[uint] =
  if self.len == 0: none(uint) else: self[^1].some

proc `$`(location: SrcLoc): string =
  $location.procedure & "[" & $location.file & ":" & $location.line & "]"

proc futureCreated(self: var ProfilerMetrics, event: Event): void =
  assert not self.partials.hasKey(event.futureId), $event.location

  self.partials[event.futureId] = RunningFuture(
    created: event.timestamp,
    state: Pending,
  )

proc bindParent(self: var ProfilerMetrics, metrics: ptr RunningFuture): void =
  let current = self.callStack.peek()
  if current.isNone:
    return

  if metrics.parent.isSome:
    assert metrics.parent.get == current.get
  metrics.parent = current

proc futureRunning(self: var ProfilerMetrics, event: Event): void = 
  assert self.partials.hasKey(event.futureId), $event.location

  self.partials.withValue(event.futureId, metrics):
    assert metrics.state == Pending or metrics.state == Paused,
      $event.location

    self.bindParent(metrics)
    self.callStack.push(event.futureId)

    metrics.lastStarted = event.timestamp
    metrics.state = Running

proc futurePaused(self: var ProfilerMetrics, event: Event): void = 
  assert self.partials.hasKey(event.futureId), $event.location
  assert event.futureId == self.callStack.pop(), $event.location

  self.partials.withValue(event.futureId, metrics):
    assert metrics.state == Running, $event.location

    let segmentExecTime = event.timestamp - metrics.lastStarted

    if metrics.pauses == 0:
      metrics.timeToFirstPause = segmentExecTime
    metrics.partialExecTime += segmentExecTime
    metrics.pauses += 1
    metrics.state = Paused

proc futureCompleted(self: var ProfilerMetrics, event: Event): void = 
  self.partials.withValue(event.futureId, metrics):
    if metrics.state == Running:
      self.futurePaused(event)

    let location = event.location
    if not self.totals.hasKey(location):
      self.totals[location] = AggregateFutureMetrics()

    self.totals.withValue(location, aggMetrics):
      let execTime = metrics.partialExecTime - metrics.partialChildrenExecOverlap
      
      aggMetrics.callCount.inc()
      aggMetrics.execTime += execTime
      aggMetrics.execTimeMax = max(aggMetrics.execTimeMax, execTime)
      aggMetrics.childrenExecTime += metrics.partialChildrenExecTime
      aggMetrics.wallClockTime += event.timestamp - metrics.created

    if metrics.parent.isSome:
      self.partials.withValue(metrics.parent.get, parentMetrics):
        parentMetrics.partialChildrenExecTime += metrics.partialExecTime
        parentMetrics.partialChildrenExecOverlap += metrics.timeToFirstPause

    self.partials.del(event.futureId)

proc processEvent*(self: var ProfilerMetrics, event: Event): void =
  case event.event:
  of Init: self.futureCreated(event)
  of Run: self.futureRunning(event)
  of Pause: self.futurePaused(event)
  of Finish: self.futureCompleted(event)

proc processAllEvents*(self: var ProfilerMetrics, events: seq[Event]): void =
  for event in events:
    self.processEvent(event)