#!/usr/bin/env bash
# Runs a two-process multiplayer race (host + client) and fails if either fails.
#   tests/run_mp_test.sh <godot> lan
#   tests/run_mp_test.sh <godot> online ws://127.0.0.1:8090
# A bad connection on either side: NETEM_CLIENT / NETEM_HOST (see Net._netem).
G=$1; KIND=$2; URL=${3:-}
cd "$(dirname "$0")/.."
LOGDIR=${LOGDIR:-/tmp}
rm -f ~/.local/share/godot/app_userdata/Apex\ Circuit/mp_code.txt
APEX_NETEM=${NETEM_HOST:-} timeout 640 $G --headless --script res://tests/mp_test.gd -- host $KIND $URL > $LOGDIR/mp_host.log 2>&1 &
H=$!
sleep 4
APEX_NETEM=${NETEM_CLIENT:-} timeout 640 $G --headless --script res://tests/mp_test.gd -- client $KIND $URL > $LOGDIR/mp_client.log 2>&1 &
C=$!
wait $H; HC=$?
wait $C; CC=$?
echo "== host (exit $HC)"; grep -E "PASS|FAIL|finished P|SCRIPT ERROR|at: res" $LOGDIR/mp_host.log
echo "== client (exit $CC)"; grep -E "PASS|FAIL|finished P|SCRIPT ERROR|at: res" $LOGDIR/mp_client.log
if [ $HC -ne 0 ] || [ $CC -ne 0 ]; then
  # (What happened, for a failure on a machine we can't look at.)
  echo "== host log, the end"; grep -E "\[[0-9.]+ s\]|FAIL|SCRIPT|closed|left" $LOGDIR/mp_host.log | tail -40
  echo "== client log, the end"; grep -E "\[[0-9.]+ s\]|FAIL|SCRIPT|closed|left" $LOGDIR/mp_client.log | tail -40
fi
[ $HC -eq 0 ] && [ $CC -eq 0 ]
