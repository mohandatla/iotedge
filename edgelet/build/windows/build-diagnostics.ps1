# Copyright (c) Microsoft. All rights reserved.

<#
 # Builds and publishes to target/publish/ the iotedge-diagnostics binary and its associated dockerfile
 #>

param(
    [ValidateSet('debug', 'release')]
    [string]$BuildConfiguration = 'release'
)

$ErrorActionPreference = 'Continue'

. (Join-Path $PSScriptRoot 'util.ps1')

$targetArchs = @('amd64', 'arm32v7', 'aarch64')

for ($i = 0; $i -lt $targetArchs.Length; $i++) {
    $Arm = ($targetArchs[$i] -eq "arm32v7")
    $Arm64 = ($targetArchs[$i] -eq "aarch64")
    Assert-Rust -Arm:$Arm -Arm64:$Arm64

    $oldPath = ''

    if ($Arm -or $Arm64) {
        if ($BuildConfiguration -eq 'debug') {
            # Arm rust compiler does not support debug build
            continue
        }

        $oldPath = ReplacePrivateRustInPath -Arm:$Arm -Arm64:$Arm64

        if($Arm64) {
            PatchRustForArm -Arm64
        }
        else {
            PatchRustForArm
        }
    }

    If ($BuildConfiguration -eq 'release') {
        $BuildConfiguration = 'release'
        $BuildConfigOption = '--release'
    }
    else {
        $BuildConfiguration = 'debug'
        $BuildConfigOption = ''
    }

    $cargo = Get-CargoCommand -Arm:$Arm -Arm64:$Arm64
    $ManifestPath = Get-Manifest

    $versionInfoFilePath = Join-Path $env:BUILD_REPOSITORY_LOCALPATH 'versionInfo.json'
    $env:VERSION = Get-Content $versionInfoFilePath | ConvertFrom-JSON | % version
    $env:NO_VALGRIND = 'true'

    $originalRustflags = $env:RUSTFLAGS
    $env:RUSTFLAGS += ' -C target-feature=+crt-static'

    $architectureTuple = ''

    if($Arm) {
        $architectureTuple = '--target thumbv7a-pc-windows-msvc'
    }
    elseif($Arm64) {
        $architectureTuple ='--target aarch64-pc-windows-msvc'
    }

    Write-Host "$cargo build -p iotedge-diagnostics $architectureTuple $BuildConfigOption --manifest-path $ManifestPath"
    Invoke-Expression "$cargo build -p iotedge-diagnostics $architectureTuple $BuildConfigOption --manifest-path $ManifestPath"
    if ($originalRustflags -eq '') {
        Remove-Item Env:\RUSTFLAGS
    }
    else {
        $env:RUSTFLAGS = $originalRustflags
    }
    if ($LastExitCode -ne 0) {
        throw "cargo build failed with exit code $LastExitCode"
    }

    if ($Arm -and (-not [string]::IsNullOrEmpty($oldPath))) {
        $env:PATH = $oldPath
    }
}

$publishFolder = [IO.Path]::Combine($env:BUILD_BINARIESDIRECTORY, 'publish', 'azureiotedge-diagnostics')

New-Item -Type Directory $publishFolder

Copy-Item -Recurse -Verbose `
    ([IO.Path]::Combine($env:BUILD_REPOSITORY_LOCALPATH, 'edgelet', 'iotedge-diagnostics', 'docker')) `
    ([IO.Path]::Combine($publishFolder, 'docker'))

Copy-Item -Verbose `
    ([IO.Path]::Combine($env:BUILD_REPOSITORY_LOCALPATH, 'edgelet', 'target', $BuildConfiguration, 'iotedge-diagnostics.exe')) `
    ([IO.Path]::Combine($publishFolder, 'docker', 'windows', 'amd64'))

Copy-Item -Verbose `
    ([IO.Path]::Combine($env:BUILD_REPOSITORY_LOCALPATH, 'edgelet', 'target', 'thumbv7a-pc-windows-msvc', $BuildConfiguration, 'iotedge-diagnostics.exe')) `
    ([IO.Path]::Combine($publishFolder, 'docker', 'windows', 'arm32v7'))

    Copy-Item -Verbose `
    ([IO.Path]::Combine($env:BUILD_REPOSITORY_LOCALPATH, 'edgelet', 'target', 'aarch64-pc-windows-msvc', $BuildConfiguration, 'iotedge-diagnostics.exe')) `
    ([IO.Path]::Combine($publishFolder, 'docker', 'windows', 'aarch64'))
$ErrorActionPreference = 'Stop'
