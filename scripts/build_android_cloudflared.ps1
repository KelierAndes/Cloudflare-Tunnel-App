<#
.SYNOPSIS
  Build the Android cloudflared runtime that ships in jniLibs/<abi>/libcloudflared.so.

.DESCRIPTION
  Android has no /etc/resolv.conf, so the official Linux binary sends DNS queries to
  [::1]:53 and fails; bionic also cannot answer SRV, which breaks edge discovery.
  This builds cloudflared with the NDK (cgo) and applies
  android/patches/cloudflared-cf_dns_server.patch (CF_DNS_SERVER support).

  Requires Go 1.27+ and the Android NDK. The source is shallow-cloned on first run.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\build_android_cloudflared.ps1
  powershell -ExecutionPolicy Bypass -File scripts\build_android_cloudflared.ps1 -GoExe C:\go\bin\go.exe -Ndk C:\Android\Sdk\ndk\28.2.13676358
#>
param(
    [string]$GoExe = 'go',
    [string]$Ndk = '',
    [string]$SourceDir = "$env:TEMP\cloudflared-android-src",
    [string]$Version = '2026.10.3',
    [string[]]$Abi = @('arm64-v8a', 'x86_64')
)

$ErrorActionPreference = 'Stop'
$project = Split-Path -Parent $PSScriptRoot
$patch = Join-Path $project 'android\patches\cloudflared-cf_dns_server.patch'

if (-not $Ndk) {
    $sdk = Join-Path $env:LOCALAPPDATA 'Android\Sdk\ndk'
    if (-not (Test-Path $sdk)) { throw "NDK not found; pass -Ndk" }
    $Ndk = (Get-ChildItem $sdk -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
}
$toolchain = Join-Path $Ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin'
if (-not (Test-Path $toolchain)) { throw "NDK toolchain not found: $toolchain" }

if (-not (Test-Path (Join-Path $SourceDir 'go.mod'))) {
    Write-Host "Cloning cloudflared source into $SourceDir"
    git clone --depth 1 --branch $Version https://github.com/cloudflare/cloudflared $SourceDir
    if ($LASTEXITCODE -ne 0) { throw "git clone failed" }
}
Push-Location $SourceDir
try {
    git apply --check $patch 2>$null
    if ($LASTEXITCODE -eq 0) {
        git apply $patch
        Write-Host "Applied CF_DNS_SERVER patch"
    }
    else {
        Write-Host "Patch already applied or not applicable; continuing"
    }

    $targets = @{
        'arm64-v8a' = @{ Arch = 'arm64'; Cc = 'aarch64-linux-android21-clang.cmd' }
        'x86_64'    = @{ Arch = 'amd64'; Cc = 'x86_64-linux-android21-clang.cmd' }
    }
    foreach ($abi in $Abi) {
        $target = $targets[$abi]
        if (-not $target) { throw "Unknown ABI: $abi" }
        $out = Join-Path $project "android\app\src\main\jniLibs\$abi\libcloudflared.so"
        Write-Host "Building $abi -> $out"
        $env:GOOS = 'android'
        $env:GOARCH = $target.Arch
        $env:CGO_ENABLED = '1'
        $env:CC = Join-Path $toolchain $target.Cc
        & $GoExe build -trimpath -ldflags "-s -w -X main.Version=$Version -X main.BuildTime=android" -o $out ./cmd/cloudflared
        if ($LASTEXITCODE -ne 0) { throw "Build failed for $abi" }
        Get-Item $out | Select-Object Name, Length | Format-Table -AutoSize
    }
}
finally {
    Pop-Location
}
