import std/tables

import ./events
import ../[timer, srcloc]

export timer, tables, srcloc

type
  Clock* = proc (): Moment

  AggregateFutureMetrics* = object
    execTime*: Duration
    childrenExecTime*: Duration
    wallClockTime*: Duration

  RunningFuture* = object
    state*: ExtendedFutureState
    created*: Moment
    lastStarted*: Moment
    timeToFirstPause*: Duration
    partialExecTime*: Duration
    pauses*: uint
    
  ProfilerMetrics* = object
    partials: Table[uint, RunningFuture]
    totals*: Table[SrcLoc, AggregateFutureMetrics]

proc init*(T: typedesc[ProfilerMetrics]): ProfilerMetrics =
  result.clock = timer.now
  result.partials = initTable[uint, RunningFuture]()
  result.totals = initTable[SrcLoc, AggregateFutureMetrics]()

proc futureCreated(self: var ProfilerMetrics, event: Event): void =
  assert not self.partials.hasKey(event.futureId)

  self.partials[event.futureId] = RunningFuture(
    created: event.timestamp,
    state: Pending,
  )

proc futureRunning(self: var ProfilerMetrics, event: Event): void = 
  assert self.partials.hasKey(event.futureId)

  self.partials.withValue(event.futureId, metrics):
    assert metrics.state == Pending or metrics.state == Paused

    metrics.lastStarted = event.timestamp
    metrics.state = Running

proc futurePaused(self: var ProfilerMetrics, event: Event): void = 
  assert self.partials.hasKey(event.futureId)

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
      aggMetrics.execTime += metrics.partialExecTime
      aggMetrics.wallClockTime += event.timestamp - metrics.created
    
  self.partials.del(event.futureId)

proc processEvent*(self: var ProfilerMetrics, event: Event): void =
  case event.newState:
  of Pending: self.futureCreated(event)
  of Running: self.futureRunning(event)
  of Paused: self.futurePaused(event)
  of Completed: self.futureCompleted(event)
  else: 
    assert false, "Unimplemented"

proc processAllEvents*(self: var ProfilerMetrics, events: seq[Event]): void =
  for event in events:
    self.processEvent(event)