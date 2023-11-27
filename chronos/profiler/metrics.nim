import std/tables
import std/options

import ./events
import ../[timer, srcloc]

export timer, tables, srcloc

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

proc futureCreated(self: var ProfilerMetrics, event: Event): void =
  assert not self.partials.hasKey(event.futureId)

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
  assert self.partials.hasKey(event.futureId)

  self.partials.withValue(event.futureId, metrics):
    assert metrics.state == Pending or metrics.state == Paused

    self.bindParent(metrics)
    self.callStack.push(event.futureId)

    metrics.lastStarted = event.timestamp
    metrics.state = Running

proc futurePaused(self: var ProfilerMetrics, event: Event): void = 
  assert self.partials.hasKey(event.futureId)
  assert event.futureId == self.callStack.pop()

  self.partials.withValue(event.futureId, metrics):
    assert metrics.state == Running

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
  case event.newState:
  of Pending: self.futureCreated(event)
  of Running: self.futureRunning(event)
  of Paused: self.futurePaused(event)
  # Completion, failure and cancellation are currently handled the same way.
  of Completed: self.futureCompleted(event)
  of Failed: self.futureCompleted(event)
  of Cancelled: self.futureCompleted(event)

proc processAllEvents*(self: var ProfilerMetrics, events: seq[Event]): void =
  for event in events:
    self.processEvent(event)