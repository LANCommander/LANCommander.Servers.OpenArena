# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/base:local
ARG BASE_IMAGE=lancommander/base:latest
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="OpenArena Game Server" \
      org.opencontainers.image.description="Dedicated server for OpenArena 0.8.8 (the official Linux oa_ded build)" \
      app.lancommander.server.kind="game" \
      app.lancommander.server.game.title="OpenArena" \
      app.lancommander.server.external-id.hq="5bfb30c6-9778-429c-9a7d-3cf63f364f60" \
      app.lancommander.server.external-id.igdb="77358"

# ----------------------------
# Server settings
#   - OA_SERVER_URL is the official OpenArena 0.8.8 release zip (game data and oa_ded.x86_64).
#     It is unpacked into /config/Server on first start and verified against OA_SERVER_SHA256
#     (empty = no check). Any zip with baseoa/pak0.pk3 and oa_ded.x86_64 works (file:// too)
#   - The OA_* settings below are written into <OA_GAME or baseoa>/lancommander.cfg on every
#     start, which the server execs at startup. Empty settings are left out
#   - The optional HTTP file server serves Merged/ for clients' HTTP downloads (OA_DOWNLOAD_URL),
#     limited to .pk3 files
# ----------------------------
ENV OA_SERVER_URL="https://download.tuxfamily.org/openarena/rel/088/openarena-0.8.8.zip" \
    OA_SERVER_SHA256="5a8faf7f5b51f351b0a1618c06b6b98a5f1a6758f1d39818de2c87df2a0bac4a" \
    OA_GAME="" \
    OA_PORT="27960" \
    OA_LAN="true" \
    OA_MAX_PLAYERS="16" \
    OA_SERVER_NAME="OpenArena Server" \
    OA_MOTD="" \
    OA_GAME_TYPE="ffa" \
    OA_MAP="oa_dm1" \
    OA_MAP_LIST="" \
    OA_FRAG_LIMIT="20" \
    OA_TIME_LIMIT="15" \
    OA_CAPTURE_LIMIT="8" \
    OA_BOTS="" \
    OA_BOT_SKILL="" \
    OA_PASSWORD="" \
    OA_RCON_PASSWORD="" \
    OA_PURE="" \
    OA_ALLOW_DOWNLOAD="1" \
    OA_DOWNLOAD_URL="" \
    HTTP_FILESERVER_ENABLED="false" \
    HTTP_FILESERVER_WEB_ROOT="/config/Merged" \
    HTTP_FILESERVER_FILE_PATTERN="^/[^/]+/[^/]+\.pk3$" \
    START_EXE="/usr/local/bin/openarena-server" \
    START_ARGS=""

# oa_ded.x86_64 only links libc, libm and libdl
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip && \
    rm -rf /var/lib/apt/lists/*

COPY Scripts/openarena-server /usr/local/bin/openarena-server
RUN chmod +x /usr/local/bin/openarena-server

COPY Hooks/ "${BASE_HOOKS}/"

# 27960/udp: game, server info queries, rcon and LAN browser (OA_PORT)
# 80/tcp:    HTTP downloads, when HTTP_FILESERVER_ENABLED=true
EXPOSE 27960/udp
EXPOSE 80/tcp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
