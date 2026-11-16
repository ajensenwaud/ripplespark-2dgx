#!/usr/bin/env bash
# stop.sh : stop the serve on every Spark (run ON the head), keeping each rank's log in logs/, and drop the GPU locks
# start.sh took. NAME= another container set (default ripple-tf / ripple-tf-follow).
set -uo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
need_pair
NAME=${NAME:-ripple-tf}
mkdir -p logs
ts=$(date +%Y%m%d-%H%M%S)
if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  docker logs "$NAME" > "logs/$NAME-$ts.log" 2>&1
  docker rm -f "$NAME" > /dev/null && log "stopped rank 0 (logs/$NAME-$ts.log)"
fi
r=1
for W in "${W_LIST[@]}"; do
  f=logs/$NAME-follow-$ts.log; (( WORLD > 2 )) && f=logs/$NAME-follow$r-$ts.log
  if ssh -n "$W" "docker ps -a --format '{{.Names}}'" | grep -qx "$NAME-follow"; then
    ssh -n "$W" "docker logs $NAME-follow" > "$f" 2>&1
    ssh -n "$W" "docker rm -f $NAME-follow > /dev/null" && log "stopped rank $r on $W ($f)"
  fi
  ssh -n "$W" "grep -q '^serve $NAME ' ~/ripple/gpu.lock 2> /dev/null && rm -f ~/ripple/gpu.lock; true"
  r=$((r + 1))
done
grep -q "^serve $NAME " ~/ripple/gpu.lock 2> /dev/null && rm -f ~/ripple/gpu.lock
log "stopped"
