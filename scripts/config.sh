# RippleSpark: Ripple-65B-Preview on two or four DGX Sparks via TensorFold. Shared settings; override in scripts/local.sh
# (gitignored).
# shellcheck disable=SC2034

# --- nodes -------------------------------------------------------------------------------------------------------
WORKER="${WORKER:-}"                          # rank 1: ssh target over the CX7 link (user@address); set in scripts/local.sh
WORKERS="${WORKERS:-}"                        # ranks 1.. in order, space-separated: three for four Sparks (default: WORKER)
MASTER="${MASTER:-}"                          # rank 0's CX7 address; set in scripts/local.sh
TP_PORT="${TP_PORT:-29681}"                  # MiMo 29661, GLM 29551, Kolibri 29561
TP_WIRE_PORT="${TP_WIRE_PORT:-29700}"        # four Sparks, ROCE=1: fabric/tp's multirank wire (it takes this port to +7)

# --- checkpoints -------------------------------------------------------------------------------------------------
SRC_REPO="ricursiveAI/Ripple-65B-Preview"
SRC_REV="da94cc013a8fda04a502f0a185083c7099ea06c1"
DRAFT_REPO="ricursiveAI/Ripple-65B-Preview-DFlash2"
DRAFT_REV="35609b3be3dd08a822b3ba1257c1ea5dd6f87632"
MODELS_ROOT="${MODELS_ROOT:-$HOME/models}"
SRC_DIR="${SRC_DIR:-$MODELS_ROOT/Ripple-65B-Preview}"
DRAFT_DIR="${DRAFT_DIR:-$MODELS_ROOT/Ripple-65B-Preview-DFlash2}"
PACK_REPO="ajensenwaud/Ripple-65B-Preview-exl3-5.0bpw"   # scripts/fetch_pack.sh
PACK_REV="${PACK_REV:-1d260f752b753d2b17571de237029b5e2251db07}"   # the uploaded 5.0 pack
PACK="${PACK:-5.0}"                          # the speed pack (6.0 the alternative)
MODEL_DIR="${MODEL_DIR:-$MODELS_ROOT/Ripple-65B-Preview-exl3-${PACK}bpw}"   # same path on both nodes
SERVED_NAME="${SERVED_NAME:-Ripple-65B-Preview}"

# --- quantiser ---------------------------------------------------------------------------------------------------
EXL3_REPO="https://github.com/auryn-macmillan/exllamav3"
EXL3_COMMIT="d71a6644e7c1b12bff56b47dd878478ee870f46f"    # 1.6.6 + feat/ricursive (value residual)
# TensorFold CUDA base (PyTorch 2.13 nv26.07, CUDA 13.3, Triton 3.7.1, NCCL, libibverbs), the MiMo/GLM base
BASE_IMAGE="${BASE_IMAGE:-ghcr.io/miaai-lab/glm-5.3-flash-exl3-2x-dgx-sparks-tensorfold@sha256:14f15591eae5d6a540f09218d3852068962fe5381371bbfefe0e9194cd834529}"
IMAGE="${IMAGE:-ripple-tf}"

# --- engine ------------------------------------------------------------------------------------------------------
TF_REPO="https://github.com/ashhart/TensorFold"
TF_TAG="v1.2.3"
TF_COMMIT="6ec5fa4cb233f3606acbdad5bec433f0f8758f96"
ZIG_TREE="${ZIG_TREE:-326a0a51a1c30f2fc59468a1b2f9c2cd6af34aee}"                     # tree hash of v1.2.3 + patches-zig/ (scripts/zig_prepare.sh checks it)
ZIG_DIR="${ZIG_DIR:-$HOME/ripple/tensorfold}"
ZIG_BUILD_IMAGE="${ZIG_BUILD_IMAGE:-ripple-zig-build:0.17.0}"

# --- serving -----------------------------------------------------------------------------------------------------
PORT="${PORT:-8888}"
HOST="${HOST:-0.0.0.0}"
STREAMS="${STREAMS:-1}"
CONTEXT="${CONTEXT:-1048576}"                # tokens a stream (the model's 1M window); 262144 with STREAMS=4
CACHE_DIR="${CACHE_DIR:-$HOME/.cache/ripple-tf}"
MAX_TOKENS="${MAX_TOKENS:-32768}"            # a reply's ceiling when a request names none
# The engine holds back a tenth of unified memory by default (12 GiB on a Spark); 4 GiB keeps the prompt cache on
# at 1M x 1 with room for the first request's growth (scripts/start.sh passes it to both ranks).
MEM_RESERVE_GIB="${MEM_RESERVE_GIB:-4}"
PROMPT_CACHE_GIB="${PROMPT_CACHE_GIB:-}"      # empty: the engine's default (16 GiB, within the room left)
GRAPHS="${GRAPHS:-1}"                         # decode rows as CUDA graphs (byte-identical to eager)
ROCE="${ROCE:-1}"                             # the ranks' small gathers by RoCE writes (byte-identical to NCCL; four Sparks: the multirank wire)
DRAFTER="${DRAFTER:-1}"                       # 1 (default): the publisher's DFlash2 drafter (BF16, cut over both ranks); 0: copies only
COPIES="${COPIES:-1}"                         # 0: no prompt-copy (n-gram) drafts (TF_RICURSIVE_COPY_DRAFTS=0)
# --- NCCL over the CX7 link (as MiMo's recipe) -------------------------------------------------------------------
NCCL_IFNAME="${NCCL_IFNAME:-enp1s0f0np0}"
NCCL_HCAS="${NCCL_HCAS:-rocep1s0f0,roceP2p1s0f0}"
NCCL_GID="${NCCL_GID:-3}"

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }
[[ -f "$(dirname "${BASH_SOURCE[0]}")/local.sh" ]] && source "$(dirname "${BASH_SOURCE[0]}")/local.sh"
# need_pair: WORKERS (or WORKER) and MASTER set; W_LIST the workers in rank order, WORLD the Sparks (2 or 4)
need_pair() {
  WORKERS=${WORKERS:-$WORKER}
  [[ -n "$WORKERS" && -n "$MASTER" ]] || die "set WORKER (two Sparks) or WORKERS (four) and MASTER in scripts/local.sh"
  read -ra W_LIST <<< "$WORKERS"
  WORLD=$((1 + ${#W_LIST[@]}))
  (( WORLD == 2 || WORLD == 4 )) || die "Ripple runs on two or four Sparks; WORKERS names ${#W_LIST[@]}"
}
true
