import os
import ../../chronos

proc child11() {.async.} =
  echo "I ran"
  await sleepAsync(10.milliseconds)

proc child2() {.async.} = 
  os.sleep(10)

proc child1() {.async.} =
  await child2()
  await child11()

proc p() {.async.} =
  echo "r1"
  await child1()
  echo "r2"