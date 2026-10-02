#!/usr/bin/env bash
set -euo pipefail

echo "=== Server report: $(hostname) ==="
echo "User: $(whoami)"
echo "IP: $(hostname -I)"
echo
echo "--- Disk ---"
df -h /
echo
echo "--- Memory ---"
free -h
