#!/usr/bin/env bash
# Runs a headless Godot test script. Prints a readable log and turns failures
# and script errors into GitHub annotations so they show on the run summary.
set -u
LOG=$(mktemp)
timeout 900 ~/godot/godot --headless --fixed-fps 120 --script "$1" > "$LOG" 2>&1
CODE=$?
grep -v -e 'Parameter "m" is null' -e 'mesh_storage.h' -e '^$' "$LOG"
grep -E "FAIL|SCRIPT ERROR|Parse Error" "$LOG" | head -20 | sed "s|^|::error title=$1::|"
if [ $CODE -ne 0 ]; then
  echo "::error title=$1::test exited with code $CODE"
fi
exit $CODE
