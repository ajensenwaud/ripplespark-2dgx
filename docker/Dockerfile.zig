# ripple-zig-build:0.17.0 -- the TensorFold Zig engine's CUDA build image: the recipe base (nvcc 13.3, CUDA headers)
# plus the official Zig release named by the engine tree's .zig-version, its sha256 checked against
# https://ziglang.org/download/index.json. Build on the head:  docker build -f docker/Dockerfile.zig -t ripple-zig-build:0.17.0 .
FROM ripple-tf:latest
ARG ZIG_VERSION=0.17.0
ARG ZIG_SHA256=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8
RUN set -eux; \
    url="https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-linux-${ZIG_VERSION}.tar.xz"; \
    python3 -c "import urllib.request,sys; urllib.request.urlretrieve(sys.argv[1], '/tmp/zig.tar.xz')" "$url"; \
    echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum -c -; \
    mkdir -p /opt/zig; tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1; rm /tmp/zig.tar.xz; \
    /opt/zig/zig version
ENV PATH=/opt/zig:$PATH
ENTRYPOINT []
