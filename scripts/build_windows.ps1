param(
    [switch]$DebugBuild
)

$ErrorActionPreference = "Stop"
$project = Split-Path -Parent $PSScriptRoot
$name = Split-Path -Leaf $project
$configArgs = @("build", "windows")
if (-not $DebugBuild) {
    $configArgs += "--release"
}

function Build-InPlace {
    param([string]$Path)
    Push-Location $Path
    try {
        flutter @configArgs
        if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }
    }
    finally {
        Pop-Location
    }
}

# MSBuild's FileTracker does not reliably handle very long paths. If the
# project lives deep under the user profile, map its parent to a short drive.
if ($project.Length -gt 80) {
    $drive = $null
    foreach ($candidate in @("R:", "S:", "T:", "U:", "V:")) {
        if (-not (Test-Path "$candidate\")) {
            $drive = $candidate
            break
        }
    }
    if (-not $drive) {
        throw "No free drive letter for a short-path build. Build from a shorter path."
    }
    Write-Host "Mapping $drive -> $project (long path workaround)"
    & subst $drive $project
    try {
        Push-Location "$drive\"
        try {
            flutter @configArgs
            if ($LASTEXITCODE -ne 0) { throw "flutter build failed" }
        }
        finally {
            Pop-Location
        }
    }
    finally {
        & subst $drive /d
    }
}
else {
    Build-InPlace $project
}

$out = Join-Path $project "build\windows\x64\runner\Release\cf_tunnel_manager.exe"
Write-Host ""
Write-Host "Build finished: $out"
