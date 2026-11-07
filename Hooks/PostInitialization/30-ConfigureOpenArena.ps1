#Requires -Modules Logging

# Write the OA_* settings into <OA_GAME or baseoa>/lancommander.cfg, which openarena-server execs
# at startup. The file is regenerated on every start and ends by starting the first map. Put your
# own settings in server.cfg next to it (in Overlay/): lancommander.cfg execs it first, so the
# OA_* settings win, or last when neither OA_MAP nor OA_MAP_LIST is set, so it starts the map.

$game = if ($Env:OA_GAME) { $Env:OA_GAME } else { 'baseoa' }
$dir = Join-Path $Env:SERVER_ROOT $game
$file = Join-Path $dir 'lancommander.cfg'

if (-not (Test-Path -Path (Join-Path $Env:SERVER_ROOT 'baseoa/pak0.pk3'))) {
    Write-Log -Level Error "baseoa/pak0.pk3 not found in $Env:SERVER_ROOT; set OA_SERVER_URL or copy OpenArena into $Env:SERVER_DIR"
    return
}

if ($game -ne 'baseoa' -and -not (Test-Path -Path $dir)) {
    Write-Log -Level Warning "OA_GAME=$game, but $dir doesn't exist; copy the mod folder into $Env:SERVER_DIR"
}

function ConvertTo-Quoted([string] $Value) { '"' + $Value.Replace('"', '').Replace(';', '') + '"' }

function ConvertTo-Bool([string] $Value) {
    if (-not $Value) { return $null }
    if ($Value -in 'true', '1', 'yes') { '1' } elseif ($Value -in 'false', '0', 'no') { '0' } else { $Value }
}

# g_gametype numbers of OpenArena 0.8.8; names are accepted too
$gameTypes = @{
    'ffa' = 0; 'dm' = 0; 'deathmatch' = 0
    'tourney' = 1; 'tournament' = 1; 'duel' = 1
    'tdm' = 3; 'teamdeathmatch' = 3
    'ctf' = 4
    '1fctf' = 5; 'oneflag' = 5
    'overload' = 6; 'obelisk' = 6
    'harvester' = 7
    'elimination' = 8; 'elim' = 8
    'ctfelimination' = 9; 'ctfelim' = 9; 'ctf_elimination' = 9
    'lms' = 10; 'lastmanstanding' = 10
    'dd' = 11; 'doubledomination' = 11; 'doubledom' = 11
    'dom' = 12; 'domination' = 12
}
$gameType = $null
if ($Env:OA_GAME_TYPE) {
    $key = $Env:OA_GAME_TYPE.Trim().ToLowerInvariant().Replace(' ', '').Replace('-', '')
    if ($key -match '^\d+$') { $gameType = $key }
    elseif ($gameTypes.ContainsKey($key)) { $gameType = [string]$gameTypes[$key] }
    else { Write-Log -Level Warning "Unknown OA_GAME_TYPE '$($Env:OA_GAME_TYPE)'; g_gametype left alone" }
}

$dedicated = if ((ConvertTo-Bool $Env:OA_LAN) -eq '0') { '2' } else { '1' }

$values = [ordered]@{
    'sv_hostname'      = $(if ($Env:OA_SERVER_NAME) { ConvertTo-Quoted $Env:OA_SERVER_NAME })
    'g_motd'           = $(if ($Env:OA_MOTD) { ConvertTo-Quoted $Env:OA_MOTD })
    'sv_maxclients'    = $Env:OA_MAX_PLAYERS
    'g_gametype'       = $gameType
    'fraglimit'        = $Env:OA_FRAG_LIMIT
    'timelimit'        = $Env:OA_TIME_LIMIT
    'capturelimit'     = $Env:OA_CAPTURE_LIMIT
    'bot_minplayers'   = $Env:OA_BOTS
    'g_spSkill'        = $Env:OA_BOT_SKILL
    'g_password'       = $(if ($Env:OA_PASSWORD) { ConvertTo-Quoted $Env:OA_PASSWORD })
    'rconPassword'     = $(if ($Env:OA_RCON_PASSWORD) { ConvertTo-Quoted $Env:OA_RCON_PASSWORD })
    'sv_pure'          = ConvertTo-Bool $Env:OA_PURE
    'sv_allowDownload' = ConvertTo-Bool $Env:OA_ALLOW_DOWNLOAD
    'sv_dlURL'         = $(if ($Env:OA_DOWNLOAD_URL) { ConvertTo-Quoted $Env:OA_DOWNLOAD_URL.TrimEnd('/') })
}

# Map rotation as a chain of vstr cvars: at the end of a match the game runs `vstr nextmap`
$maps = @($Env:OA_MAP_LIST -split '[\s,;]+' | Where-Object { $_ })
$start = $Env:OA_MAP

$lines = @('// Generated from the OA_* environment variables on every start, edit server.cfg instead')

$serverCfg = Join-Path $dir 'server.cfg'
$hasServerCfg = Test-Path -Path $serverCfg
$startsMap = $start -or $maps

if ($hasServerCfg -and $startsMap) { $lines += 'exec server.cfg' }

# Read-only on the command line, and the launcher sets it there; here it's informational
$lines += "// dedicated $dedicated (OA_LAN=$($Env:OA_LAN)) is set by openarena-server"

foreach ($key in $values.Keys) {
    if ($null -ne $values[$key] -and $values[$key] -ne '') { $lines += "set $key $($values[$key])" }
}

if ($maps) {
    for ($i = 0; $i -lt $maps.Count; $i++) {
        $next = ($i + 1) % $maps.Count
        $lines += "set lc_map$i `"map $($maps[$i]); set nextmap vstr lc_map$next`""
    }
    $index = if ($start) { [array]::IndexOf([string[]]($maps | ForEach-Object { $_.ToLowerInvariant() }), $start.ToLowerInvariant()) } else { 0 }
    if ($index -ge 0) {
        $lines += "vstr lc_map$index"
    } else {
        # OA_MAP isn't in the rotation: play it first, then continue with the rotation. Loading a
        # map resets nextmap, so it has to be set after the map command, like in the lc_map slots
        $lines += "set lc_start `"map $start; set nextmap vstr lc_map0`""
        $lines += "vstr lc_start"
    }
    Write-Log "Map rotation: $($maps -join ', ')"
} elseif ($start) {
    $lines += "map $start"
} elseif ($hasServerCfg) {
    $lines += 'exec server.cfg'
} else {
    Write-Log -Level Warning "OA_MAP and OA_MAP_LIST are empty and there is no $game/server.cfg, so no map will be started"
}

New-Item -ItemType Directory -Path $dir -Force | Out-Null
[System.IO.File]::WriteAllText($file, ($lines -join "`n") + "`n")
# Not -R: a recursive chown through Merged/ would copy every pk3 up into Overlay/
chown "$($Env:UID):$($Env:GID)" $file

Write-Log "Wrote OA_* settings to $file"
