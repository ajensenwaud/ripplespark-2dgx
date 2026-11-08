#!/usr/bin/env bash
# stop.sh : stop the serve on both Sparks (run ON the head), keeping both ranks' logs in logs/, and drop the GPU
# locks start.sh took. NAME= another container pair (default ripple-tf / ripple-tf-follow).
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
need_pair
NAME=${NAME:-ripple-tf}
W=$WORKER
mkdir -p logs
ts=$(date +%Y%m%d-%H%M%S)
if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  docker logs "$NAME" > "logs/$NAME-$ts.log" 2>&1
  docker rm -f "$NAME" > /dev/null && log "stopped rank 0 (logs/$NAME-$ts.log)"
fi
if ssh -n "$W" "docker ps -a --format '{{.Names}}'" | grep -qx "$NAME-follow"; then
  ssh -n "$W" "docker logs $NAME-follow" > "logs/$NAME-follow-$ts.log" 2>&1
  ssh -n "$W" "docker rm -f $NAME-follow > /dev/null" && log "stopped rank 1 on $W (logs/$NAME-follow-$ts.log)"
fi
grep -q "^serve $NAME " ~/ripple/gpu.lock 2> /dev/null && rm -f ~/ripple/gpu.lock
ssh -n "$W" "grep -q '^serve $NAME ' ~/ripple/gpu.lock 2> /dev/null && rm -f ~/ripple/gpu.lock; true"
log "stopped"
