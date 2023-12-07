import std/tables
import std/options
import std/sets

import ./events
import ../[timer, srcloc]

export timer, tables, sets, srcloc

type
  AggregateFutureMetrics* = object
    execTime*: Duration
    execTimeMax*: Duration
    childrenExecTime*: Duration
    wallClockTime*: Duration
    zombieEventCount*: uint
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

proc isZombie(self: var ProfilerMetrics, event: Event): bool =
  # The first precondition for a zombie future is that it should not have
  # an entry in the partial metrics table.
  if self.partials.hasKey(event.futureId):
    return false

  # The second precondition is that it must have been completed at least once.
  # Since we're not tracking IDs for individual completed futures cause that 
  # would use up a lot of memory, we test if at least one future of this "type"
  # (i.e. at the same location) has been completed. If that's not satisfied,
  # this positively is a bug.
  assert self.totals.hasKey(event.location), $event.location

  self.totals.withValue(event.location, aggMetrics):
    # Count zombie events. We can't tell how many events are issued by a single
    # zombie future (we think it's one, but who knows) so can't really rely on 
    # this being a count of the actual zombie futures.
    aggMetrics.zombieEventCount.inc()

  true

proc futureRunning(self: var ProfilerMetrics, event: Event): void =
  if self.isZombie(event): return

  self.partials.withValue(event.futureId, metrics):
    assert metrics.state == Pending or metrics.state == Paused,
      $event.location & " " & $metrics.state

    self.bindParent(metrics)
    self.callStack.push(event.futureId)

    metrics.lastStarted = event.timestamp
    metrics.state = Running

proc futurePaused(self: var ProfilerMetrics, event: Event): void = 
  if self.isZombie(event): return

  assert event.futureId == self.callStack.pop(), $event.location

  self.partials.withValue(event.futureId, metrics):
    assert metrics.state == Running, $event.location & " " & $metrics.state

    let segmentExecTime = event.timestamp - metrics.lastStarted

    if metrics.pauses == 0:
      metrics.timeToFirstPause = segmentExecTime
    metrics.partialExecTime += segmentExecTime
    metrics.pauses += 1
    metrics.state = Paused

proc futureCompleted(self: var ProfilerMetrics, event: Event): void =
  assert self.partials.hasKey(event.futureId), $event.location

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