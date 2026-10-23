FROM ubuntu:24.04 AS base

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

FROM base AS builder

RUN curl -fsSL https://cli.moonbitlang.com/install/unix.sh -o /tmp/install-moon.sh \
    && bash /tmp/install-moon.sh
ENV PATH="/root/.moon/bin:${PATH}"
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
# Resolve the example's test dependency from this checkout.
COPY moon.mod moon.pkg compose.mbt container.mbt docker.mbt ./
COPY example ./example
RUN moon work init . example \
    && moon update \
    && moon build --target wasm --release example/main

FROM base

COPY --from=builder /root/.moon/bin/moonrun /usr/local/bin/moonrun
COPY --from=builder /workspace/_build/wasm/release/build/moonbit-community/testdock-example/main/main.wasm /app/main.wasm

EXPOSE 3000
CMD ["moonrun", "/app/main.wasm"]
