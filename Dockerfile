ARG BUILD_FROM
FROM ghcr.io/activepieces/activepieces:0.79.3 AS activepieces

FROM ${BUILD_FROM}

# Install nginx
RUN apt-get update \
    && apt-get install -y --no-install-recommends nginx procps \
    && rm -rf /var/lib/apt/lists/*

# Copy Node.js and Bun runtimes from the Activepieces image
COPY --from=activepieces /usr/local/bin/node /usr/local/bin/node
COPY --from=activepieces /usr/local/lib/node_modules /usr/local/lib/node_modules
COPY --from=activepieces /usr/local/bin/bun /usr/local/bin/bun
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -sf /usr/local/bin/bun /usr/local/bin/bunx

# Copy Activepieces application and frontend from official image
COPY --from=activepieces /usr/src/app /usr/src/app
COPY --from=activepieces /usr/share/nginx/html /usr/share/nginx/html

# Copy root filesystem overlay
COPY rootfs /
