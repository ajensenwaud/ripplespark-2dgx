#!/usr/bin/env bash
# start.sh : serve Ripple-65B-Preview on both Sparks (TensorFold's native server, TP=2), run ON the head (rank 0).
# Rank 1 (`tf-ricursive follow`) starts on the worker first, then rank 0 (`tensorfold-native serve`) here on :$PORT;
# both in Docker (ripple-tf-follow, ripple-tf) from $IMAGE with the built zig-out mounted. Waits for /v1/models and
# sends one warm-up chat. Takes ~/ripple/gpu.lock on both nodes (kept while serving; ./stop.sh drops it).
#   scripts/start.sh                         1 stream x 1,048,576 tokens (the default: the model's served window)
#   STREAMS=4 CONTEXT=262144 scripts/start.sh  4 streams x 256K
# Env: PACK (5.0 | 6.0), PORT, BIN (a zig-out), MEM_RESERVE_GIB, PROMPT_CACHE_GIB, GRAPHS, ROCE, NAME (container),
#      DRAFTER (1: DFlash2 drafter from DRAFT_DIR), COPIES (0: no prompt-copy drafts), SERVE_ARGS (extra serve flags,
#      e.g. --loop-guard).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
need_pair
BIN=${BIN:-$ZIG_DIR/zig-out}
NAME=${NAME:-ripple-tf}
W=$WORKER
LOCK=$HOME/ripple/gpu.lock
TAG="serve $NAME :$PORT $(date -Is)"
[[ -x $BIN/native/bin/tensorfold-native && -x $BIN/bin/tf-ricursive ]] || die "no build in $BIN (scripts/zig_build.sh native ricursive-cuda)"
[[ -f $MODEL_DIR/config.json ]] || die "no pack at $MODEL_DIR"
ssh -n "$W" "test -f $MODEL_DIR/config.json" || die "the worker has no pack at $MODEL_DIR"
ss -ltn "( sport = :$PORT )" | grep -q LISTEN && die "port $PORT is taken"
( set -o noclobber; echo "$TAG" > "$LOCK" ) 2> /dev/null || die "head GPU busy: $(cat "$LOCK")"
ssh -n "$W" "( set -o noclobber; echo '$TAG' > ~/ripple/gpu.lock ) 2> /dev/null" || { rm -f "$LOCK"; die "worker GPU busy: $(ssh -n "$W" cat ~/ripple/gpu.lock)"; }
fail() { docker rm -f "$NAME" > /dev/null 2>&1 || true; ssh -n "$W" "docker rm -f $NAME-follow > /dev/null 2>&1; rm -f ~/ripple/gpu.lock"; rm -f "$LOCK"; die "$@"; }
# the same build on both nodes
D=$(dirname "$BIN"); ssh -n "$W" "mkdir -p ${D#$HOME/}"; rsync -a "$BIN" "$W:${D#$HOME/}/"
a=$(sha256sum "$BIN/native/bin/tensorfold-native" "$BIN/bin/tf-ricursive" | cut -c1-16 | tr '\n' ' ')
b=$(ssh -n "$W" "sha256sum $BIN/native/bin/tensorfold-native $BIN/bin/tf-ricursive" | cut -c1-16 | tr '\n' ' ')
[[ $a == "$b" ]] || fail "builds differ: head $a, worker $b"
run_args() { # RANK: both ranks' container settings (NCCL over the CX7 RoCE link, as MiMo's recipe)
  echo "--gpus all --ipc=host --network host --device /dev/infiniband --cap-add IPC_LOCK --ulimit memlock=-1" \
    "--user $(id -u):$(id -g) -e HOME=/tmp -v $MODEL_DIR:$MODEL_DIR:ro -v $D:$D:ro" \
    "-e NCCL_COMM_ID=$MASTER:$TP_PORT -e NCCL_SOCKET_IFNAME=$NCCL_IFNAME -e NCCL_IB_HCA=$NCCL_HCAS" \
    "-e NCCL_IB_GID_INDEX=$NCCL_GID -e TF_ROCE_GID_INDEX=$NCCL_GID -e NCCL_MIN_NCHANNELS=4 -e NCCL_MAX_NCHANNELS=4" \
    "-e TF_RICURSIVE_RANK=$1 -e TF_RICURSIVE_WORLD=2 -e TF_RICURSIVE_CONTEXT=$CONTEXT -e TF_RICURSIVE_SLOTS=$STREAMS" \
    "-e TF_RICURSIVE_GRAPHS=$GRAPHS -e TF_RICURSIVE_ROCE=$ROCE -e TENSORFOLD_MEMORY_RESERVE_GIB=$MEM_RESERVE_GIB ${EXTRA_ENV:-}"
}
mkdir -p logs
[[ $COPIES == 0 ]] && EXTRA_ENV="${EXTRA_ENV:-} -e TF_RICURSIVE_COPY_DRAFTS=0"
# the drafter's share on rank 1 too (cuda_draft.zig cuts it over the ranks as the target)
d1=""; [[ $DRAFTER == 1 ]] && d1="-v $DRAFT_DIR:$DRAFT_DIR:ro -e TF_RICURSIVE_DRAFTER=$DRAFT_DIR"
log "rank 1 on $W: $(basename "$MODEL_DIR"), $STREAMS x $CONTEXT tokens"
ssh -n "$W" "docker rm -f $NAME-follow > /dev/null 2>&1; docker run -d --name $NAME-follow $(run_args 1) $d1 \
  --entrypoint $BIN/bin/tf-ricursive $IMAGE:latest $MODEL_DIR follow > /dev/null" || fail "rank 1 did not start"
log "rank 0 here on :$PORT"
pc=${PROMPT_CACHE_GIB:+--prompt-cache-gib $PROMPT_CACHE_GIB}
dm=""; if [[ $DRAFTER == 1 ]]; then [[ -f $DRAFT_DIR/config.json ]] || fail "no drafter at $DRAFT_DIR"; dm="-v $DRAFT_DIR:$DRAFT_DIR:ro"; pc="$pc --drafter $DRAFT_DIR"; fi
# shellcheck disable=SC2046,SC2086
docker run -d --name "$NAME" $(run_args 0) $dm --entrypoint "$BIN/native/bin/tensorfold-native" "$IMAGE:latest" \
  serve "$MODEL_DIR" --host "$HOST" --port "$PORT" --name "$SERVED_NAME" --parallel "$STREAMS" --context "$CONTEXT" \
  --max-tokens "$MAX_TOKENS" $pc ${SERVE_ARGS:-} > /dev/null || fail "rank 0 did not start"
{ echo "# $(date -Is) scripts/start.sh"; echo "pack $MODEL_DIR"; echo "build $BIN $a"; echo "rank0 $(run_args 0)"
  echo "serve --parallel $STREAMS --context $CONTEXT --max-tokens $MAX_TOKENS $pc ${SERVE_ARGS:-}"; } > logs/serve-config.txt
for i in $(seq 1 360); do
  if curl -fsS -m 3 "http://127.0.0.1:$PORT/v1/models" > /dev/null 2>&1; then
    log "up after $((i * 5)) s"
    log "engine: $(docker logs "$NAME" 2>&1 | grep -m1 'CUDA sm_' | sed 's/^\[tensorfold\] //' | cut -c1-400)"
    log "MemAvailable head $(awk '/MemAvailable/{printf "%.1f", $2/1048576}' /proc/meminfo) GiB, worker $(ssh -n "$W" "awk '/MemAvailable/{printf \"%.1f\", \$2/1048576}' /proc/meminfo") GiB"
    out=$(curl -fsS -m 600 "http://127.0.0.1:$PORT/v1/chat/completions" -H 'Content-Type: application/json' \
      -d "{\"model\": \"$SERVED_NAME\", \"messages\": [{\"role\": \"user\", \"content\": \"Say hello in five words.\"}], \"max_tokens\": 512, \"temperature\": 0}") \
      || fail "warm-up request failed: docker logs $NAME"
    log "warm-up: $(python3 -c 'import json,sys; j=json.loads(sys.argv[1]); print(repr(j["choices"][0]["message"].get("content"))[:200], j["usage"])' "$out")"
    log "serving $SERVED_NAME at http://$(hostname):$PORT/v1"
    exit 0
  fi
  docker inspect -f '{{.State.Running}}' "$NAME" 2> /dev/null | grep -q true || { docker logs --tail 30 "$NAME"; fail "rank 0 exited"; }
  if (( i % 6 == 0 )); then
    ssh -n "$W" "docker inspect -f '{{.State.Running}}' $NAME-follow 2> /dev/null" | grep -q true || { ssh -n "$W" "docker logs --tail 30 $NAME-follow"; fail "rank 1 exited"; }
  fi
  sleep 5
done
fail "not up after 30 min: docker logs $NAME"
