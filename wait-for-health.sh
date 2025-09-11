#!/usr/bin/env bash
set -e
URL="${1:-http://localhost:3000/health}"
TRIES=30
SLEEP=2
echo "Waiting for $URL ..."
for i in $(seq 1 $TRIES); do
  if curl -fsS "$URL" >/dev/null 2>&1; then
    echo "Healthy!"
    exit 0
  fi
  echo "not ready ($i/$TRIES), sleeping $SLEEP sec..."
  sleep $SLEEP
done
echo "Service not healthy."
exit 1
