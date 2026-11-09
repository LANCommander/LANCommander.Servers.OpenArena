---
sidebar_label: Docker
---

# OpenArena Docker Container

This Docker container runs an OpenArena dedicated server. It is built on the base image and runs the official OpenArena 0.8.8 Linux server (`oa_ded.x86_64`, `ioq3+oa 1.36_SVN1910M`). The release zip is downloaded on first start and includes all game data, so you don't need to supply game files.

## Quick Start

```yaml
services:
  openarena:
    image: lancommander/openarena:latest
    container_name: openarena

    ports:
      - 27960:27960/udp

    volumes:
      - "/data/Servers/OpenArena/Deathmatch:/config"

    environment:
      OA_SERVER_NAME: "My OpenArena Server"
      OA_GAME_TYPE: "ffa"
      OA_MAP_LIST: "oa_dm1 oa_dm3 oa_dm5 aggressor wrackdm17"
      OA_BOTS: "4"
      OA_RCON_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

## How It Starts

1. `PostInitialization/20-InstallOpenArena.ps1` downloads `OA_SERVER_URL` if `Server/oa_ded.x86_64` or `Server/baseoa/pak0.pk3` is missing or the URL changed, checks `OA_SERVER_SHA256`, unpacks the folder holding `oa_ded.x86_64` into `Server/` (without the client and Windows binaries) and remounts the overlay.
2. `PostInitialization/30-ConfigureOpenArena.ps1` writes the non-empty `OA_*` settings and the map rotation into `<OA_GAME or baseoa>/lancommander.cfg`. It does this through `Merged/`, so the file lands in `Overlay/`.
3. `START_EXE` (`/usr/local/bin/openarena-server`) runs `./oa_ded.x86_64 +set dedicated <1|2> +set net_port <OA_PORT> +set fs_basepath Merged +set fs_homepath Merged +set fs_game <OA_GAME> <START_ARGS> +exec lancommander.cfg` from `Merged/`, line-buffered so its console output reaches `docker logs` straight away. `lancommander.cfg` ends by starting the first map.

A successful start ends with:

```
execing lancommander.cfg
sv_maxclients will be changed upon restarting.
g_gametype will be changed upon restarting.
------ Server Initialization ------
Server: oa_dm1
...
InitGame: \version\ioq3+oa 1.36_SVN1910M linux-x86_64 Dec 25 2011\protocol\71\...
```

## Configuration Options

### Ports

- **27960/udp**: Game, server info queries, rcon and LAN browser (`OA_PORT`, `net_port`).
- **80/tcp**: HTTP downloads, only with `HTTP_FILESERVER_ENABLED=true`.

### Environment Variables

See the [README](../README.md#environment-variables) for the full table and the game type names.

### server.cfg and lancommander.cfg

`lancommander.cfg` is regenerated on every start; don't edit it. Put your own settings in `Overlay/<OA_GAME or baseoa>/server.cfg` (`set g_instantgib 1`, `set g_delagHitscan 1`, `set g_doWarmup 1`, ...):

- With `OA_MAP` or `OA_MAP_LIST` set, `lancommander.cfg` execs `server.cfg` first, then applies the `OA_*` settings (which win) and starts the map. Leave an `OA_*` setting empty to control it from `server.cfg`.
- With both empty, `lancommander.cfg` applies the `OA_*` settings and execs `server.cfg` last, so `server.cfg` must start a map itself (and can set up its own rotation).

### Map rotation

OpenArena runs `vstr nextmap` at the end of a match. `OA_MAP_LIST` becomes a chain of cvars:

```
set lc_map0 "map oa_ctf4ish; set nextmap vstr lc_map1"
set lc_map1 "map ps37ctf2; set nextmap vstr lc_map0"
vstr lc_map1
```

Loading a map resets `nextmap`, so it must be set after the `map` command (inside the same vstr), never before it. The hook starts at `OA_MAP` when it is in the list; otherwise it plays `OA_MAP` once and then the list. `rcon vstr nextmap` skips to the next map.

### Bots

`OA_BOTS` sets `bot_minplayers`: bots join or leave to keep that many players. In team game types it counts **per team**, so `OA_BOTS=4` in CTF gives 8 bots. Bots use player slots (`OA_MAX_PLAYERS`). `OA_BOT_SKILL` (`g_spSkill`, 1-5) sets their skill.

### Remote administration

In the game console: `/rconpassword <OA_RCON_PASSWORD>`, then `/rcon status`, `/rcon map oa_dm4`, `/rcon kick <name>`, `/rcon g_gametype 4` followed by `/rcon map_restart`. Out of game, any Quake 3 rcon tool works on UDP 27960.

### HTTP downloads

Clients can fetch missing custom `.pk3` files over HTTP instead of the slow in-game UDP download: set `HTTP_FILESERVER_ENABLED=true`, `OA_DOWNLOAD_URL=http://<server ip>` and keep `OA_ALLOW_DOWNLOAD=1`. The file server only allows `<game>/<name>.pk3` paths.

### Hooks

| Hook | When |
|------|------|
| `PreInstallOpenArena` / `PostInstallOpenArena` | Around the OpenArena download |

Put `.ps1` scripts in `config/Scripts/Hooks/<HookName>/`.

## Match Statistics

The server can report the matches played on it to LANCommander, with the
[LANCommander match statistics plugin](https://github.com/LANCommander/LANCommander.MatchStatistics.QMM).
The plugin runs in [QMM2](https://github.com/thecybermind/qmm2), and both are built into the image. They are
turned on when `MATCH_STATS_SERVER_URL` and `MATCH_STATS_TOKEN` are set. QMM2 then takes the place of the game
module, `baseoa/qagamex86_64.so`, and loads the game's own module (kept as `qmm_qagamex86_64.so`) and the plugin. Turned off, the
game's own module is put back.

| Variable | Description | Default |
|----------|-------------|---------|
| `MATCH_STATS_ENABLED` | `auto`: on when `MATCH_STATS_SERVER_URL` and `MATCH_STATS_TOKEN` are set. `true` or `false` | `auto` |
| `MATCH_STATS_SERVER_URL` | The LANCommander server, e.g. `http://lancommander.lan:1337`. Only `http://` works on Linux | *(empty)* |
| `MATCH_STATS_TOKEN` | A LANCommander access token with the **Report matches** scope (Profile → Access Tokens). It isn't written to any file | *(empty)* |
| `MATCH_STATS_GAME_ID` | The game's id in LANCommander | *(empty)* |
| `MATCH_STATS_SERVER_ID` | This server's id in LANCommander, if LANCommander manages it | *(empty)* |
| `MATCH_STATS_MIN_PLAYERS` | Human players needed before a match is recorded | *(1)* |
| `MATCH_STATS_RECORD_BOTS` | Record bots as players (`true`/`false`) | *(true)* |
| `MATCH_STATS_RECORD_CHAT` | Record chat messages (`true`/`false`) | *(false)* |
| `QMM_MOD_DIR` | The folder of the mod the server runs (its `fs_game`) | `OA_GAME`, or `baseoa` |
| `QMM_PLUGINS` | More QMM2 plugins to load, comma-separated, relative to `QMM_MOD_DIR` | *(empty)* |

The settings are written to `baseoa/lancommander_qmm.cfg` as `lc_*` cvars on every start, and QMM2 execs it once
the plugin has loaded. Settings left empty aren't written, so they and the plugin's other `lc_*` cvars (see its
README) can be set in `server.cfg` instead, with `set`. A `qmm2.json` you put in `Overlay/baseoa/` yourself is
left alone.

`+set vm_game 0` is added to the command line so the engine loads QMM2, which then runs the game's `vm/qagame.qvm` itself. OpenArena uses the plugin's Quake III module.

`lc_status` on the server console or over RCON shows the match being recorded and how delivery is going. Reports
that couldn't be delivered yet are kept in `Overlay/baseoa/qmmaddons/lancommander/.interposer/Matches/` and sent
once LANCommander can be reached.

## Troubleshooting

- **`SHA256 mismatch`**: `OA_SERVER_URL` points at a different zip than the official `openarena-0.8.8.zip`. Clear `OA_SERVER_SHA256` (or set the zip's hash).
- **The same map plays over and over**: a hand-written rotation sets `nextmap` before the `map` command; see [Map rotation](#map-rotation).
- **Twice as many bots as expected**: `bot_minplayers` is per team in team game types; see [Bots](#bots).
- **Clients get "Server uses protocol version 71" or can't connect**: they need OpenArena 0.8.8. 0.8.1 and older use protocol 68.
- **The server isn't in the in-game LAN list**: the LAN browser broadcasts to ports 27960-27963 on the local network, so the container has to be on the LAN (macvlan/ipvlan or host networking) and `OA_PORT` in that range. Joining by IP always works.
- **`Playerstore: Failed to restore player. Invalid guid`** for every bot: harmless, bots have no GUID.
- **`couldn't exec q3config_server.cfg` / `couldn't exec autoexec.cfg`** at startup: harmless; neither file exists until you create one.
