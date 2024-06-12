import ../chronos/config

when chronosProfiling:
  import ../chronos/profiler

  import ./profiler/testevents
  import ./profiler/testmetrics

{.used.}
{.warning[UnusedImport]:off.}
