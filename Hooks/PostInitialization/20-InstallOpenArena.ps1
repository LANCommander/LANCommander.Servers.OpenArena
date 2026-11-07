#Requires -Modules Logging
#Requires -Modules Hooks
#Requires -Modules OverlayFS

# Install OpenArena from OA_SERVER_URL (a .zip with baseoa/pak0.pk3 and oa_ded.x86_64, at its root
# or in one subfolder) into Server/. Reinstalls when OA_SERVER_URL changes; the URL of the
# installed package is kept in Server/.oa-server-url. The client binaries and Windows files are
# left out. Files already in Server/ are overwritten by the package, so put your own server.cfg,
# maps and mods in Overlay/.

Invoke-Hook "PreInstallOpenArena"

$exe    = Join-Path $Env:SERVER_DIR 'oa_ded.x86_64'
$pak0   = Join-Path $Env:SERVER_DIR 'baseoa/pak0.pk3'
$marker = Join-Path $Env:SERVER_DIR '.oa-server-url'
$installed = if (Test-Path -Path $marker) { (Get-Content -Path $marker -Raw).Trim() }

if ((Test-Path -Path $exe) -and (Test-Path -Path $pak0) -and (-not $Env:OA_SERVER_URL -or $installed -eq $Env:OA_SERVER_URL -or -not $installed)) {
    Write-Log "OpenArena found in $Env:SERVER_DIR"
} elseif (-not $Env:OA_SERVER_URL) {
    Write-Log -Level Error "oa_ded.x86_64 or baseoa/pak0.pk3 not found in $Env:SERVER_DIR and OA_SERVER_URL is empty"
} else {
    Write-Log "Downloading OpenArena from $Env:OA_SERVER_URL"

    $file    = '/tmp/openarena.zip'
    $extract = '/tmp/openarena'

    curl -fsSL --retry 3 --output $file "$Env:OA_SERVER_URL"
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $Env:OA_SERVER_URL" }

    if ($Env:OA_SERVER_SHA256) {
        $hash = (Get-FileHash -Path $file -Algorithm SHA256).Hash
        if ($hash -ne $Env:OA_SERVER_SHA256) {
            Remove-Item -Force -Path $file
            throw "SHA256 mismatch for $Env:OA_SERVER_URL`: got $hash, expected $Env:OA_SERVER_SHA256 (clear OA_SERVER_SHA256 when installing from another zip)"
        }
    }

    Remove-Item -Recurse -Force -Path $extract -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $extract -Force | Out-Null
    # Client binaries, Windows binaries and DLLs aren't needed by the server
    unzip -q -o $file -d $extract -x '*.exe' '*.dll' '*openarena.*' '*oa_ded.i386'
    if ($LASTEXITCODE -gt 1) { throw "Could not extract $file" }

    $root = Get-ChildItem -Path $extract -Filter 'oa_ded.x86_64' -Recurse -File -Depth 2 |
        Select-Object -First 1 -ExpandProperty Directory
    if (-not $root) { throw "oa_ded.x86_64 not found in $Env:OA_SERVER_URL" }
    if (-not (Test-Path -Path (Join-Path $root.FullName 'baseoa/pak0.pk3'))) { throw "baseoa/pak0.pk3 not found next to oa_ded.x86_64 in $Env:OA_SERVER_URL" }

    New-Item -ItemType Directory -Path $Env:SERVER_DIR -Force | Out-Null
    cp -a "$($root.FullName)/." "$Env:SERVER_DIR/"
    if ($LASTEXITCODE -ne 0) { throw "Could not copy OpenArena into $Env:SERVER_DIR" }

    Remove-Item -Recurse -Force -Path $file, $extract

    # Zip entries can carry odd Unix modes; make the data readable and the server executable
    chmod -R u+rwX,go+rX $Env:SERVER_DIR
    chmod +x $exe
    Set-Content -Path $marker -Value $Env:OA_SERVER_URL
    chown -R "$($Env:UID):$($Env:GID)" $Env:SERVER_DIR

    # The overlay was mounted before Server/ was populated, and overlayfs doesn't reliably show
    # lower-dir changes made while mounted.
    mountpoint -q $Env:SERVER_ROOT
    if ($LASTEXITCODE -eq 0) {
        umount $Env:SERVER_ROOT
        Remove-Item -Path "$Env:WORK_DIR/*" -Recurse -Force -ErrorAction SilentlyContinue
        Mount-Overlay -MountPoint $Env:SERVER_ROOT -LowerDir $Env:SERVER_DIR -UpperDir $Env:OVERLAY_DIR -WorkDir $Env:WORK_DIR -RequireEmptyWorkDir -OverlayOption "xino=on"
        Write-Log "OverlayFS remounted"
    }

    Write-Log "OpenArena installed into $Env:SERVER_DIR"
}

Invoke-Hook "PostInstallOpenArena"

Set-Location $Env:SERVER_ROOT
