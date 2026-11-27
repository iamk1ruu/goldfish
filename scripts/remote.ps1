<#
.SYNOPSIS
  Runs a build step on the Mac from Windows: copy the source, run, copy results back.

.EXAMPLE
  scripts\remote.ps1 -Action test   -MacHost ec2-user@1.2.3.4 -Key C:\keys\mac.pem
  scripts\remote.ps1 -Action build  # uses GOLDFISH_MAC_HOST and GOLDFISH_MAC_KEY
  scripts\remote.ps1 -Action shots
  scripts\remote.ps1 -Action secrets  # copies GoogleService-Info.plist once

.NOTES
  Uses the OpenSSH and tar.exe built into Windows. Copies the files Git would track, so
  git-ignored files (the Firebase plist, build output) are never sent except by -Action secrets.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('bootstrap', 'test', 'build', 'shots', 'secrets')]
    [string]$Action,
    [string]$MacHost = $env:GOLDFISH_MAC_HOST,
    [string]$Key = $env:GOLDFISH_MAC_KEY,
    [string]$RemoteDir = 'goldfish'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $MacHost) { throw 'Pass -MacHost user@host or set GOLDFISH_MAC_HOST.' }

$sshOptions = @('-o', 'ServerAliveInterval=30')
if ($Key) { $sshOptions += @('-i', $Key) }

function Invoke-Remote([string]$command) {
    & ssh @sshOptions $MacHost $command
    if ($LASTEXITCODE -ne 0) { throw "Remote command failed ($LASTEXITCODE): $command" }
}

function Copy-ToMac([string]$local, [string]$remote) {
    & scp @sshOptions $local "${MacHost}:$remote"
    if ($LASTEXITCODE -ne 0) { throw "Copy to Mac failed: $local" }
}

function Copy-FromMac([string]$remote, [string]$local, [switch]$Recurse) {
    $flags = @()
    if ($Recurse) { $flags += '-r' }
    & scp @sshOptions @flags "${MacHost}:$remote" $local
    if ($LASTEXITCODE -ne 0) { throw "Copy from Mac failed: $remote" }
}

Push-Location $root
try {
    if ($Action -eq 'secrets') {
        $plist = Join-Path $root 'App\Resources\GoogleService-Info.plist'
        if (-not (Test-Path $plist)) { throw "Missing $plist" }
        Invoke-Remote "mkdir -p $RemoteDir/App/Resources"
        Copy-ToMac $plist "$RemoteDir/App/Resources/GoogleService-Info.plist"
        Write-Host 'Firebase config copied to the Mac.'
        return
    }

    # Pack tracked and untracked-but-not-ignored files.
    $list = Join-Path $env:TEMP 'goldfish-files.txt'
    $archive = Join-Path $env:TEMP 'goldfish-src.tar.gz'
    git ls-files --cached --others --exclude-standard | Where-Object { Test-Path $_ } | Set-Content -Encoding ascii $list
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed. Is this a Git repository?' }
    & tar.exe -czf $archive -T $list
    if ($LASTEXITCODE -ne 0) { throw 'tar failed' }

    Copy-ToMac $archive 'goldfish-src.tar.gz'
    Invoke-Remote "mkdir -p $RemoteDir && tar -xzf goldfish-src.tar.gz -C $RemoteDir && rm goldfish-src.tar.gz"

    switch ($Action) {
        'bootstrap' { Invoke-Remote "cd $RemoteDir && bash scripts/bootstrap-mac.sh" }
        'test' { Invoke-Remote "cd $RemoteDir && bash scripts/test-core.sh" }
        'build' {
            Invoke-Remote "cd $RemoteDir && bash scripts/build-ipa.sh"
            New-Item -ItemType Directory -Force (Join-Path $root 'build') | Out-Null
            Copy-FromMac "$RemoteDir/build/Goldfish-unsigned.ipa" (Join-Path $root 'build\Goldfish-unsigned.ipa')
            Write-Host 'Copied build\Goldfish-unsigned.ipa. Drag it into Sideloadly to install.'
        }
        'shots' {
            Invoke-Remote "cd $RemoteDir && bash scripts/screenshots.sh"
            New-Item -ItemType Directory -Force (Join-Path $root 'screenshots') | Out-Null
            Copy-FromMac "$RemoteDir/screenshots/*.png" (Join-Path $root 'screenshots\')
            Write-Host 'Screenshots copied to screenshots\.'
        }
    }
}
finally {
    Pop-Location
}
