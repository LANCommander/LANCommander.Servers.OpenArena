# syntax=docker/dockerfile:1.7

# Override to build against a locally built base, e.g. lancommander/base:local
ARG BASE_IMAGE=lancommander/base:latest

# ----------------------------
# QMM2 (https://github.com/thecybermind/qmm2), the plugin manager the match statistics plugin runs
# in. Built on Debian 12 like the base image, because the upstream Linux builds need glibc 2.38.
# QMM2_COMMIT is the commit LANCommander.MatchStatistics.QMM is built against.
# The sed fixes QMM2's console output (its own messages and the plugin's, lc_status too), which it
# hands to the engine through a pointer into a temporary string that is already freed
# ----------------------------
FROM debian:bookworm-slim AS qmm2

ARG QMM2_COMMIT=c60ac2392f4983c944971e71292c45235d6cedaf
ARG QMM_SDKS_COMMIT=30c923f3b6a589418f8be995eeb439089940efcd

RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates git make g++ && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git init -q qmm2 && git -C qmm2 fetch -q --depth 1 https://github.com/thecybermind/qmm2 "$QMM2_COMMIT" && git -C qmm2 checkout -q FETCH_HEAD && \
    git init -q qmm_sdks && git -C qmm_sdks fetch -q --depth 1 https://github.com/thecybermind/qmm_sdks "$QMM_SDKS_COMMIT" && git -C qmm_sdks checkout -q FETCH_HEAD && \
    sed -i 's|intptr_t args\[\] = { (intptr_t)Log::log_format(metadata, message, false).c_str() };|std::string line = Log::log_format(metadata, message, false); intptr_t args[] = { (intptr_t)line.c_str() };|' qmm2/src/qmm.cpp && \
    grep -q 'intptr_t)line.c_str()' qmm2/src/qmm.cpp && \
    make -C qmm2 -j"$(nproc)" release64

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

# ----------------------------
# LANCommander match statistics (https://github.com/LANCommander/LANCommander.MatchStatistics.QMM)
#   - MATCH_STATS_ENABLED: auto (on when MATCH_STATS_SERVER_URL and MATCH_STATS_TOKEN are set),
#     true or false. When on, QMM2 is loaded in place of the game module and loads the plugin
#   - The MATCH_STATS_* settings become lc_* cvars in <QMM_MOD_DIR>/lancommander_qmm.cfg. Empty
#     settings are left out, so they can be set in server.cfg instead
#   - QMM_MOD_DIR is the folder of the mod the server runs (fs_game), empty for OA_GAME (or baseoa)
# ----------------------------
ENV MATCH_STATS_ENABLED="auto" \
    MATCH_STATS_SERVER_URL="" \
    MATCH_STATS_TOKEN="" \
    MATCH_STATS_GAME_ID="" \
    MATCH_STATS_SERVER_ID="" \
    MATCH_STATS_MIN_PLAYERS="" \
    MATCH_STATS_RECORD_BOTS="" \
    MATCH_STATS_RECORD_CHAT="" \
    QMM_GAME="Q3A" \
    QMM_MOD_DIR="" \
    QMM_MOD_FILE="qagamex86_64.so" \
    QMM_PLUGIN="lancommander_qmm_x86_64_Q3A.so" \
    QMM_MOD="" \
    QMM_PLUGINS="" \
    QMM_VM_GAME="0"

# oa_ded.x86_64 only links libc, libm and libdl
RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        unzip && \
    rm -rf /var/lib/apt/lists/*

COPY Scripts/openarena-server /usr/local/bin/openarena-server
RUN chmod +x /usr/local/bin/openarena-server

ARG MATCH_STATS_VERSION=1.0.0
ARG MATCH_STATS_SHA256=f7a01c2ed6ebbf5af3416ea661e1cfcbbace2a89ec167c22deca400d39108cbb

ADD --checksum=sha256:${MATCH_STATS_SHA256} \
    https://github.com/LANCommander/LANCommander.MatchStatistics.QMM/releases/download/v${MATCH_STATS_VERSION}/LANCommander.QMM.MatchStatistics-v${MATCH_STATS_VERSION}.zip \
    /tmp/match-stats.zip

COPY --from=qmm2 /src/qmm2/bin/release/x86_64/qmm2_x86_64.so /opt/qmm/qmm2.so

RUN unzip -q -j /tmp/match-stats.zip "qmmaddons/lancommander/${QMM_PLUGIN}" -d /opt/qmm && \
    rm /tmp/match-stats.zip

COPY Hooks/ "${BASE_HOOKS}/"

# 27960/udp: game, server info queries, rcon and LAN browser (OA_PORT)
# 80/tcp:    HTTP downloads, when HTTP_FILESERVER_ENABLED=true
EXPOSE 27960/udp
EXPOSE 80/tcp

WORKDIR /config
ENTRYPOINT ["/usr/local/bin/entrypoint.ps1"]
