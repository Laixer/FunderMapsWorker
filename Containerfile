# Stage 1: Build tippecanoe
FROM docker.io/debian:bookworm-slim AS tippecanoe-builder

RUN apt-get update && apt-get install -y \
    git build-essential libsqlite3-dev zlib1g-dev \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/felt/tippecanoe.git /tippecanoe \
    && cd /tippecanoe \
    && make -j$(nproc) \
    && make install

# Stage 2: Runtime
FROM docker.io/oven/bun:1-debian

RUN apt-get update && apt-get install -y \
    gdal-bin \
    libsqlite3-0 \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=tippecanoe-builder /usr/local/bin/tippecanoe /usr/local/bin/
COPY --from=tippecanoe-builder /usr/local/bin/tile-join /usr/local/bin/

WORKDIR /app

COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile 2>/dev/null || bun install

COPY src/ src/
COPY tsconfig.json ./

CMD ["bun", "run", "src/index.ts"]
