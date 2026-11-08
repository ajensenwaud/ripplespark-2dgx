#!/usr/bin/env bash
# Quantise one EXL3 pack on this node (resumable: rerun the same command). Run detached:
#   setsid nohup scripts/quantise.sh 5.0 > quantise.log 2>&1 < /dev/null &
# tools/convert.py wraps exllamav3's converter (CuTe DSL argv trap); the TF32 cuBLAS override is removed for the run.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/config.sh
bits=${1:?usage: scripts/quantise.sh <bits> [src dir] [out dir]}
src=${2:-$SRC_DIR}
out=${3:-$MODELS_ROOT/Ripple-65B-Preview-exl3-${bits}bpw}
work="${WORK_ROOT:-$HOME/ripple/quant-work}/$(basename "$out")"
EXPECT_MATS=${EXPECT_MATS:-641}              # 80 layers x 8 projections + lm_head
docker image inspect "$IMAGE:latest" >/dev/null 2>&1 || die "no $IMAGE image: run scripts/prepare.sh"
[[ -f "$src/config.json" ]] || die "no source at $src"
mkdir -p "$work" "$out" "$CACHE_DIR"
resume=(); [[ -f "$work/args.json" ]] && resume=(-r)
log "$bits bpw: converting ${resume[*]:+(resuming) }$src -> $out"
docker run --rm --name "ripple-quant-$bits" --gpus all --ipc=host --shm-size 16g \
  -e PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True \
  -v "$src:/src:ro" -v "$MODELS_ROOT:$MODELS_ROOT:ro" -v "$work:/work" -v "$out:/out" -v "$CACHE_DIR:/root/.cache" -v "$PWD/tools:/tools:ro" \
  --entrypoint env "$IMAGE:latest" -u TORCH_ALLOW_TF32_CUBLAS_OVERRIDE python3 /tools/convert.py \
  -i /src -w /work -o /out -b "$bits" -hb 8 -cr 250 -cc 2048 -cb mul1 "${resume[@]}"
[[ -f "$out/quantization_config.json" ]] || die "$bits bpw: the converter exited without writing a pack"
for f in chat_template.jinja; do [[ -f "$out/$f" ]] || cp "$src/$f" "$out/"; done
docker run --rm -v "$out:/p:ro" -v "$PWD/tools:/tools:ro" --entrypoint python3 "$IMAGE:latest" \
  /tools/verify_exl3_pack.py /p "$EXPECT_MATS"
log "$bits bpw: done, $(du -sh "$out" | cut -f1)"
