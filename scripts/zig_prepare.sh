#!/usr/bin/env bash
# zig_prepare.sh : build the engine the recipe serves, run ON the head (rank 0). TensorFold at the pinned release plus
# patches-zig/, compiled for GB10 (sm_121) inside the ripple-zig-build image (nothing is installed on the hosts),
# then copied to the worker. start.sh runs $ZIG_DIR/zig-out.
set -euo pipefail
cd "$(dirname "$0")/.."
RECIPE=$(pwd)
source scripts/config.sh
need_pair
docker image inspect "$IMAGE:latest" >/dev/null 2>&1 || die "no $IMAGE image: run scripts/prepare.sh first"

# 1. TensorFold at the pinned release, the patches on a fresh branch
[[ -d "$ZIG_DIR/.git" ]] || { log "cloning TensorFold into $ZIG_DIR"; git clone -q "$TF_REPO" "$ZIG_DIR"; }
cd "$ZIG_DIR"
git fetch -q --tags origin
[[ "$(git rev-parse "$TF_TAG^{commit}")" == "$TF_COMMIT" ]] || die "$TF_TAG is not $TF_COMMIT"
git checkout -q -f -B ripplespark "$TF_COMMIT"
log "applying $(ls "$RECIPE"/patches-zig/*.patch | wc -l) patches"
GIT_COMMITTER_NAME=recipe GIT_COMMITTER_EMAIL=recipe@localhost git am -q --3way "$RECIPE"/patches-zig/*.patch \
  || { git am --abort; die "patches-zig/ did not apply"; }
TREE=$(git rev-parse HEAD^{tree})
[[ "$TREE" == "$ZIG_TREE" ]] || die "patched tree $TREE is not the pinned $ZIG_TREE"

# 2. the build image: the recipe image plus Zig (docker/Dockerfile.zig)
docker image inspect "$ZIG_BUILD_IMAGE" >/dev/null 2>&1 || {
  log "building $ZIG_BUILD_IMAGE"; docker build -q -t "$ZIG_BUILD_IMAGE" -f "$RECIPE/docker/Dockerfile.zig" "$RECIPE/docker" >/dev/null; }

# 3. compile: the native server and rank 1's follower (a few minutes the first time)
log "compiling"
rm -rf "$ZIG_DIR/zig-out"
mkdir -p "$CACHE_DIR/zig"
docker run --rm --user "$(id -u):$(id -g)" -e HOME=/tmp -e ZIG_GLOBAL_CACHE_DIR=/zc -v "$CACHE_DIR/zig:/zc" \
  -v "$ZIG_DIR:/w" -w /w "$ZIG_BUILD_IMAGE" bash -c \
  'git config --global --add safe.directory /w; zig build native ricursive-cuda -Doptimize=fast -Dnvcc=$(which nvcc) -Dsm=121'
[[ -x zig-out/native/bin/tensorfold-native && -x zig-out/bin/tf-ricursive ]] || die "build incomplete"

# 4. the same build on the worker
ssh "$WORKER" "mkdir -p $ZIG_DIR" </dev/null
rsync -a --delete zig-out/ "$WORKER:$ZIG_DIR/zig-out/"
log "built $(git rev-parse --short HEAD) (tree $TREE) in $ZIG_DIR/zig-out on both nodes; start it with scripts/start.sh"
