#!/usr/bin/env bash
# fetch_pack.sh : download the model and the drafter from Hugging Face at pinned revisions, run ON the head (rank 0).
# curl only, every file checked against the Hub's sha256; then copied to the worker over CX7 and the pack verified
# on both nodes. PACK_REPO / PACK_REV / DRAFT_REPO / DRAFT_REV are in scripts/config.sh.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
need_pair
[[ -n "${PACK_REV:-}" ]] || die "no PACK_REV pinned in scripts/config.sh"
JOBS=4 scripts/fetch_source.sh "$PACK_REPO" "$PACK_REV" "$MODEL_DIR"
JOBS=2 scripts/fetch_source.sh "$DRAFT_REPO" "$DRAFT_REV" "$DRAFT_DIR"
ssh "$WORKER" "mkdir -p $MODELS_ROOT" </dev/null
rsync -a "$MODEL_DIR" "$DRAFT_DIR" "$WORKER:$MODELS_ROOT/"
docker run --rm -v "$MODEL_DIR:/p:ro" -v "$(pwd)/tools:/tools:ro" --entrypoint python3 "$IMAGE:latest" \
  /tools/verify_exl3_pack.py /p 641 || die "pack check failed"
[[ -z "$(rsync -anci "$MODEL_DIR" "$DRAFT_DIR" "$WORKER:$MODELS_ROOT/")" ]] || die "the worker's copy differs"
log "$PACK_REPO@$PACK_REV and the drafter are on both nodes"
