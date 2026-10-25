<#
.SYNOPSIS
  Place the cloudflared runtime that should be bundled into assets/bin before a build.

.EXAMPLE
  powershell -File scripts\stage_runtime.ps1 -Platform windows
  powershell -File scripts\stage_runtime.ps1 -Platform linux
  powershell -File scripts\stage_runtime.ps1 -Platform none   # placeholder, app downloads at runtime
#>
param(
    [ValidateSet('windows', 'linux', 'none')]
    [string]$Platform = 'windows',
    [string]$Source = ''
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $project 'assets\bin'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

Get-ChildItem $dir -Filter 'cloudflared*' | Remove-Item -Force

switch ($Platform) {
    'windows' {
        $target = Join-Path $dir 'cloudflared.exe'
        if ($Source -and (Test-Path $Source)) {
            Copy-Item $Source $target -Force
        }
        elseif (Test-Path $target) {
            Write-Host "keeping existing $target"
        }
        else {
            $url = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
            Write-Host "downloading $url"
            Invoke-WebRequest -Uri $url -OutFile $target
        }
    }
    'linux' {
        $target = Join-Path $dir 'cloudflared'
        if ($Source -and (Test-Path $Source)) {
            Copy-Item $Source $target -Force
        }
        else {
            $url = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64'
            Write-Host "downloading $url"
            Invoke-WebRequest -Uri $url -OutFile $target
        }
    }
    'none' {
        # The asset directory must not be empty; the app treats a <1 MB file as "not bundled".
        Set-Content -Path (Join-Path $dir 'cloudflared') -Value 'placeholder' -NoNewline
    }
}

Get-ChildItem $dir | Select-Object Name, Length | Format-Table -AutoSize
