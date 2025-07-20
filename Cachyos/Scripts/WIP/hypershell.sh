#!/usr/bin/env bash
set -e

# Number of warmup and benchmark runs
WARMUP=5
RUNS=10

echo "== Non‑interactive startup =="
hyperfine \
  --warmup "$WARMUP" \
  --runs "$RUNS" \
  'dash -c exit' \
  'bash -c exit'

echo
echo "== Million‑iteration shell loop =="
hyperfine \
  --warmup "$WARMUP" \
  --runs "$RUNS" \
  'dash -c '\''i=1; while [ $i -le 1000000 ]; do :; i=$((i+1)); done'\''' \
  'bash -c '\''i=1; while [ $i -le 1000000 ]; do :; i=$((i+1)); done'\'''

