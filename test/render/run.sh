#!/bin/sh
# Renders hostile markdown through Qt's real renderer and fails if anything is
# fetched. The two CONTROL payloads skip the filter and must be fetched, which
# shows the check can see a request. Needs qml6 (qt6-declarative) and python3.
set -u
here=$(cd "$(dirname "$0")" && pwd)
if ss -ltn 2>/dev/null | grep -q ":8765 "; then echo "FAIL: port 8765 is already in use"; exit 1; fi
log=$(mktemp)
python3 "$here/server.py" >"$log" 2>&1 &
server=$!
sleep 1
QT_QPA_PLATFORM=offscreen timeout 30 qml6 "$here/payloads.qml" >/dev/null 2>&1
sleep 1
kill "$server" 2>/dev/null
leaked=$(grep -v "control-" "$log" || true)
if ! grep -q "control-inline" "$log"; then echo "FAIL: the control image was not fetched, so this check cannot see requests"; rm -f "$log"; exit 1; fi
rm -f "$log"
if [ -n "$leaked" ]; then echo "FAIL: filtered markdown caused requests:"; echo "$leaked"; exit 1; fi
echo "ok: no filtered payload caused a request"
