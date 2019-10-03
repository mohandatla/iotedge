# Copyright (c) Microsoft. All rights reserved.

param(
    [switch] $Release,
    [switch] $Arm,
	[switch] $Arm64
)

# Bring in util functions
$util = Join-Path -Path $PSScriptRoot -ChildPath "util.ps1"
. $util

# Ensure rust is installed
Assert-Rust -Arm:$Arm -Arm64:$Arm64

$cargo = Get-CargoCommand -Arm:$Arm -Arm64:$Arm64
Write-Host $cargo

$oldPath = if ($Arm -or $Arm64) { ReplacePrivateRustInPath -Arm:$Arm -Arm64:$Arm64} else { '' }

$ErrorActionPreference = 'Continue'

if ($Arm) {
    PatchRustForArm -OpenSSL
}
elseif($Arm64) {
    PatchRustForArm -OpenSSL -Arm64
}
# Run cargo build by specifying the manifest file

$ManifestPath = Get-Manifest

$architectureTuple = ''

if($Arm) {
    $architectureTuple = '--target thumbv7a-pc-windows-msvc'
}
elseif($Arm64) {
    $architectureTuple ='--target aarch64-pc-windows-msvc'
}

Write-Host "$cargo build --all $architectureTuple $(if ($Release) { '--release' }) --manifest-path $ManifestPath"
Invoke-Expression "$cargo build --all $architectureTuple $(if ($Release) { '--release' }) --manifest-path $ManifestPath"

if ($LastExitCode -ne 0) {
    Throw "cargo build failed with exit code $LastExitCode"
}

$ErrorActionPreference = 'Stop'

if (($Arm -or $Arm64) -and (-not [string]::IsNullOrEmpty($oldPath))) {
    $env:PATH = $oldPath
}
