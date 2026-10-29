#!/usr/bin/env bash
# Runs a two-process multiplayer race (host + client) and fails if either fails.
#   tests/run_mp_test.sh <godot> lan
#   tests/run_mp_test.sh <godot> online ws://127.0.0.1:8090
G=$1; KIND=$2; URL=${3:-}
cd "$(dirname "$0")/.."
LOGDIR=${LOGDIR:-/tmp}
rm -f ~/.local/share/godot/app_userdata/Apex\ Circuit/mp_code.txt
timeout 640 $G --headless --script res://tests/mp_test.gd -- host $KIND $URL > $LOGDIR/mp_host.log 2>&1 &
H=$!
sleep 4
timeout 640 $G --headless --script res://tests/mp_test.gd -- client $KIND $URL > $LOGDIR/mp_client.log 2>&1 &
C=$!
wait $H; HC=$?
wait $C; CC=$?
echo "== host (exit $HC)"; grep -E "PASS|FAIL|finished P|SCRIPT ERROR|at: res" $LOGDIR/mp_host.log
echo "== client (exit $CC)"; grep -E "PASS|FAIL|finished P|SCRIPT ERROR|at: res" $LOGDIR/mp_client.log
[ $HC -eq 0 ] && [ $CC -eq 0 ]
