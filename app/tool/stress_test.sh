#!/usr/bin/env bash
# Run one test file (or one test in it) many times on a deliberately busy
# machine, to find out whether it is reliable before CI does.
# See docs/writing-tests.md, "Before you push a test that touches time or files".
#
#   tool/stress_test.sh test/folder_watch_test.dart            # 20 runs
#   tool/stress_test.sh test/folder_watch_test.dart 50         # 50 runs
#   tool/stress_test.sh test/folder_watch_test.dart 20 "burst" # one test
#
# The load is one busy loop per CPU, which is roughly what a shared CI runner
# feels like to a test: timers fire late and file events arrive in clumps.
# Run from app/.
set -u
file=${1:?usage: tool/stress_test.sh <test file> [runs] [test name]}
runs=${2:-20}
name=${3:-}
cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
pids=()
for _ in $(seq "$cpus"); do (while :; do :; done) & pids+=($!); done
trap 'kill "${pids[@]}" 2>/dev/null' EXIT
fails=0
for i in $(seq "$runs"); do
  if [ -n "$name" ]; then
    flutter test "$file" --plain-name "$name" --reporter silent >/dev/null 2>&1
  else
    flutter test "$file" --reporter silent >/dev/null 2>&1
  fi
  if [ $? -ne 0 ]; then fails=$((fails + 1)); echo "run $i: FAILED"; fi
done
echo "$file: $fails of $runs runs failed under load"
[ "$fails" -eq 0 ]
