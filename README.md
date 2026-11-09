# OpenArena Server (Docker)

This repository provides a Dockerized **OpenArena** dedicated server. On first start it downloads the official [OpenArena 0.8.8](https://openarena.ws/) release, which holds both the game data and the Linux dedicated server (`oa_ded.x86_64`), so you don't need to supply any files. OpenArena is free software (GPLv2 engine and game code, free content).
The image builds on [`lancommander/base`](https://github.com/LANCommander/LANCommander.Servers.Base). It supports file overlaying using OverlayFS.

---

## Features

- The official OpenArena 0.8.8 Linux server, installed from the release zip (sha256-checked) or any zip of an OpenArena install
- Every 0.8.8 game type: Free For All, Tournament, Team Deathmatch, CTF, One Flag CTF, Overload, Harvester, Elimination, CTF Elimination, Last Man Standing, Double Domination and Domination
- The server's name, game type, map, map rotation, limits, bots and passwords are environment variables, written into a config file the server execs at startup
- LAN-only by default; one setting announces it to the internet master servers
- Optional HTTP file server for clients' fast downloads of custom `.pk3` files
- Supports file overlaying using OverlayFS (no file copying required)

## Docker Compose Example

```yaml
services:
  openarena:
    image: lancommander/openarena:latest
    container_name: openarena

    ports:
      - "27960:27960/udp"

    volumes:
      - ./config:/config

    environment:
      OA_SERVER_NAME: "My OpenArena Server"
      OA_GAME_TYPE: "ctf"
      OA_MAP: "oa_ctf4ish"
      OA_MAP_LIST: "oa_ctf4ish ps37ctf2 pul1ctf czest2ctf"
      OA_BOTS: "2"
      OA_RCON_PASSWORD: "changeme"

    user: root
    cap_add:
      - SYS_ADMIN
    security_opt:
      - apparmor:unconfined

    restart: unless-stopped
```

The in-game LAN browser (Multiplayer → Server: Local) finds servers by broadcasting to ports 27960-27963. That needs the container on the LAN itself (macvlan/ipvlan, or `network_mode: host`); with port mapping, clients join by IP (Multiplayer → Specify, or `/connect <ip>` in the console).

---

## Game Files

On first start `PostInitialization/20-InstallOpenArena.ps1` downloads `OA_SERVER_URL` (430 MB), checks it against `OA_SERVER_SHA256` and unpacks `oa_ded.x86_64`, `baseoa/` and `missionpack/` into `config/Server/` (about 410 MB). The client and Windows binaries are left out. It reinstalls only when `OA_SERVER_URL` changes.

To install from your own copy instead, point `OA_SERVER_URL` at a zip of an OpenArena 0.8.8 install (with `oa_ded.x86_64` and `baseoa/pak0.pk3` at its root or in one folder), e.g. a mounted LANCommander archive as `file:///path/to/archive.zip`, and clear `OA_SERVER_SHA256`. Or copy the files into `config/Server/` yourself; the hook then leaves them alone.

Clients must run the same version: OpenArena 0.8.8 (protocol 71).

## Directory Layout (Host)

```text
.
└── config/
    ├── Server/            # OpenArena: oa_ded.x86_64, baseoa/pak*.pk3, missionpack/
    ├── Overlay/           # Your files, layered on top of Server/ (baseoa/server.cfg, custom pk3s, generated lancommander.cfg, logs)
    ├── Merged/            # Overlayfs merged view (auto-created, the server runs here)
    └── Scripts/
        └── Hooks/         # PowerShell scripts run at container lifecycle hooks
```

---

## Environment Variables

These are in addition to the [base image's variables](https://github.com/LANCommander/LANCommander.Servers.Base#environment).
The settings are written into `<OA_GAME or baseoa>/lancommander.cfg` on every start. Settings left empty are left out, so you can set them in `server.cfg` next to it instead.

| Variable | Description | Default |
|----------|-------------|---------|
| `OA_SERVER_URL` | Zip to install OpenArena from (`http(s)://` or `file://`) | the official 0.8.8 release zip |
| `OA_SERVER_SHA256` | Expected SHA-256 of the zip; empty skips the check | hash of `openarena-0.8.8.zip` |
| `OA_GAME` | `fs_game`: empty for `baseoa`, `missionpack`, or a mod folder | |
| `OA_PORT` | `net_port` (game port) | `27960` |
| `OA_LAN` | `true`: `dedicated 1`, LAN only. `false`: `dedicated 2`, announced to the internet master servers | `true` |
| `OA_MAX_PLAYERS` | `sv_maxclients`, the player slots (bots take slots too) | `16` |
| `OA_SERVER_NAME` | `sv_hostname` | `OpenArena Server` |
| `OA_MOTD` | `g_motd`, shown to players while connecting | |
| `OA_GAME_TYPE` | `g_gametype`, as a number or name (see below) | `ffa` |
| `OA_MAP` | First map. Empty with `OA_MAP_LIST` set starts with the rotation's first map | `oa_dm1` |
| `OA_MAP_LIST` | Map rotation, separated by spaces or commas. When `OA_MAP` isn't in it, `OA_MAP` is played first | |
| `OA_FRAG_LIMIT` | `fraglimit` (0 = none) | `20` |
| `OA_TIME_LIMIT` | `timelimit` in minutes (0 = none) | `15` |
| `OA_CAPTURE_LIMIT` | `capturelimit`, captures that end a CTF-style map (0 = none) | `8` |
| `OA_BOTS` | `bot_minplayers`: bots fill the server up to this many players; in team modes **per team** | |
| `OA_BOT_SKILL` | `g_spSkill`, bot skill `1` to `5` | |
| `OA_PASSWORD` | `g_password`, required to join | |
| `OA_RCON_PASSWORD` | `rconPassword`; empty disables remote console | |
| `OA_PURE` | `sv_pure`: `1` makes clients use the server's pk3s only | |
| `OA_ALLOW_DOWNLOAD` | `sv_allowDownload`: clients may download missing pk3s from the server | `1` |
| `OA_DOWNLOAD_URL` | `sv_dlURL`, base URL for HTTP downloads (e.g. `http://<server ip>`) | |
| `HTTP_FILESERVER_ENABLED` | Serve `Merged/` on port 80 for `OA_DOWNLOAD_URL` | `false` |
| `HTTP_FILESERVER_WEB_ROOT` | Directory served by the HTTP file server | `/config/Merged` |
| `HTTP_FILESERVER_FILE_PATTERN` | Regex of paths the HTTP file server allows | `.pk3` files in game folders |
| `START_EXE` | Launcher | `/usr/local/bin/openarena-server` |
| `START_ARGS` | Extra command line, inserted before `+exec lancommander.cfg` (e.g. `+set g_instantgib 1`) | |

### Game types

| `OA_GAME_TYPE` | `g_gametype` | Stock maps |
|----------------|--------------|------------|
| `ffa` / `dm` | 0 | `oa_dm1`, `oa_dm2`…`oa_dm5`, `oa_dm7`, `aggressor`, `wrackdm17`, `oa_rpg3dm2`, `kaos2`, `am_galmevish2`, `oa_shouse` |
| `tourney` | 1 | `pul1duel-oa`, `oa_dm4`, `oa_dm6`, `oa_dm7`, `aggressor`, `am_underworks`, `oa_minia`, `slimefac` |
| `tdm` | 3 | `oa_dm1`, `oa_dm3`, `oa_dm5`, `kaos2`, `czest1dm`, `oa_shouse`, `sleekgrinder`, `pxlfan` |
| `ctf` | 4 | `oasago2`, `oa_ctf4ish`, `ps37ctf2`, `pul1ctf`, `czest2ctf`, `czest3ctf`, `am_lavactf`, `oa_bases3`, `ps9ctf` |
| `1fctf` / `overload` / `harvester` | 5 / 6 / 7 | most CTF maps: `oasago2`, `oa_ctf4ish`, `ps37ctf2`, `pul1ctf`, `oa_bases3`, `oa_bases7` |
| `elimination` | 8 | `oa_dm6`, `czest1dm`, `oa_shouse`, `am_underworks2`, `oa_minia` and most CTF maps |
| `ctfelim` | 9 | the CTF maps |
| `lms` | 10 | the FFA maps |
| `dd` | 11 | most CTF maps, `oa_shouse`, `oa_minia` |
| `dom` | 12 | `aggressor`, `oa_koth2`, `oa_shouse`, `sleekgrinder`, `am_lavaarena`, `oa_thor` |

The game types a map supports are listed in its `.arena` script (`scripts/arenas.txt` and the `scripts/*.arena` files in the pk3s). The server still loads a map for a game type it doesn't list.

See [Documentation/Docker.md](Documentation/Docker.md) for more detail.

---

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

---

## Building

```bash
docker build -t lancommander/openarena:local .
docker build --build-arg BASE_IMAGE=lancommander/base:local -t lancommander/openarena:local .
```

---

## License

OpenArena is free software: its engine and game code are GPLv2 and its content is under free licenses (see `COPYING` and `CREDITS` in the release). It is downloaded at runtime and not included in the image.
This repository contains only Docker build logic and helper scripts licensed under MIT.
