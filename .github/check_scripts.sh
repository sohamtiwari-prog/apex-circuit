#!/usr/bin/env bash
# Compile-checks every GDScript file so syntax errors fail the build early
# with a clear message.
GODOT=${GODOT:-~/godot/godot}
FAIL=0
for f in scripts/*.gd; do
  OUT=$($GODOT --headless --check-only --script "res://$f" 2>&1 | grep -E "SCRIPT ERROR|Parse Error|at: GDScript" | grep -v mesh_storage)
  if [ -n "$OUT" ]; then
    echo "FAIL $f"; echo "$OUT"
    echo "$OUT" | grep -E "Parse Error" | head -3 | sed "s|^|::error file=$f::|"
    FAIL=1
  else
    echo "ok   $f"
  fi
done
exit $FAIL
