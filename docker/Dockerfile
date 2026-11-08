# RippleSpark image: the TensorFold CUDA base plus exllamav3 with the ricursive architecture (quantiser and
# reference forward). The Zig engine is built separately (scripts/zig_prepare.sh) and runs in this image.
ARG BASE_IMAGE
FROM ${BASE_IMAGE}

# --no-deps: the base's PyTorch is an NVIDIA build that pip must never replace.
ARG EXL3_REPO
ARG EXL3_COMMIT
ARG MAX_JOBS=12
RUN git clone -q "${EXL3_REPO}" /opt/exllamav3 && git -C /opt/exllamav3 checkout -q "${EXL3_COMMIT}" \
 && cd /opt/exllamav3 && TORCH_CUDA_ARCH_LIST="12.1" MAX_JOBS=${MAX_JOBS} \
    pip install --no-deps --no-build-isolation --no-cache-dir . \
 && pip install --no-deps --no-cache-dir marisa_trie llguidance \
 && cd / && python3 -c "import exllamav3, exllamav3_ext; from exllamav3.architecture.architectures import get_architectures; \
from importlib.metadata import version; assert 'RicursiveForCausalLM' in get_architectures(); print('exllamav3', version('exllamav3'))"

COPY tools /opt/ripple/tools
LABEL org.opencontainers.image.title="ripple-tf" io.exllamav3.revision="${EXL3_COMMIT}"
WORKDIR /workspace
