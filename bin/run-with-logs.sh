#!/bin/bash
# Rilancia DockDock da /Applications e mostra i log in tempo reale.
# Uso: bash bin/run-with-logs.sh

cd "$(dirname "$0")/.."

pkill -x DockDock 2>/dev/null
sleep 0.5

open /Applications/DockDock.app

echo ""
echo "=== DockDock logs (Ctrl+C per fermare) ==="
echo ""

log stream \
  --predicate 'subsystem == "com.alBz.DockDock"' \
  --level debug \
  --style compact
