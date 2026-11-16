#!/usr/bin/env bash
# Pull the base, build the ripple-tf image on the head (rank 0), then copy it to every worker over CX7.
# Nothing is installed on the hosts.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
need_pair
docker pull -q "$BASE_IMAGE" >/dev/null
log "building $IMAGE (exllamav3 $EXL3_COMMIT)"
DOCKER_BUILDKIT=0 docker build -q -t "$IMAGE:latest" --build-arg BASE_IMAGE="$BASE_IMAGE" \
  --build-arg EXL3_REPO="$EXL3_REPO" --build-arg EXL3_COMMIT="$EXL3_COMMIT" -f docker/Dockerfile . >/dev/null
# save/load under the containerd store changes the image ID, so compare the layer digests
LAYERS='{{range .RootFS.Layers}}{{println .}}{{end}}'
SUM=$(docker image inspect "$IMAGE:latest" --format "$LAYERS" | sha256sum | cut -c1-16)
for W in "${W_LIST[@]}"; do
  log "built $SUM; copying to $W"
  docker save "$IMAGE:latest" | gzip -1 | ssh "$W" 'gunzip | docker load -q'
  [[ "$(ssh -n "$W" "docker image inspect $IMAGE:latest --format '$LAYERS'" | sha256sum | cut -c1-16)" == "$SUM" ]] \
    || die "$W image layers differ"
done
log "ready on $WORLD nodes: layers $SUM"
