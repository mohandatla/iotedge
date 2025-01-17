# Copyright (c) Microsoft. All rights reserved.

New-Item -Type Directory -Force '~/.cargo/bin'
$env:PATH += ";$(Resolve-Path '~/.cargo/bin')"

function Test-RustUp
{
    (get-command -Name rustup.exe -ErrorAction SilentlyContinue) -ne $null
}

function GetPrivateRustPath
{
    Join-Path -Path (Get-IotEdgeFolder) -ChildPath 'rust-windows-arm/rust-windows-arm/bin/'
}

function GetPrivateRustPathForArm64
{
    Join-Path -Path (Get-IotEdgeFolder) -ChildPath 'rust-windows-arm64/rust-windows-arm64/bin/'
}

function Get-CargoCommand
{
    param (
        [switch] $Arm,
        [switch] $Arm64
    )

    if ($Arm) {
        # we have private rust arm tool chain downloaded and unzipped to <source root>\rust-windows-arm\rust-windows-arm\cargo.exe
        Join-Path -Path (GetPrivateRustPath) -ChildPath 'cargo.exe'
    }
    elseif($Arm64) {
        Join-Path -Path (GetPrivateRustPathForArm64) -ChildPath 'cargo.exe'
    }
    elseif (Test-RustUp) {
        'cargo +stable-x86_64-pc-windows-msvc '
    }
    else {
        "$env:USERPROFILE/.cargo/bin/cargo.exe +stable-x86_64-pc-windows-msvc "
    }
}

function Get-Manifest
{
    $ProjectRoot = Join-Path -Path $PSScriptRoot -ChildPath "../../.."
    Join-Path -Path $ProjectRoot -ChildPath "edgelet/Cargo.toml"
}

function Get-EdgeletFolder
{
    $ProjectRoot = Join-Path -Path $PSScriptRoot -ChildPath "../../.."
    Join-Path -Path $ProjectRoot -ChildPath "edgelet"
}

function Get-IotEdgeFolder
{
    # iotedge is parent folder of edgelet
    Join-Path -Path $(Get-EdgeletFolder) -ChildPath ".."
}

function Assert-Rust
{
    param (
        [switch] $Arm,
        [switch] $Arm64
    )

    $ErrorActionPreference = 'Continue'

    if ($Arm) {
        if (-not (Test-Path 'rust-windows-arm')) {
            # if the folder rust-windows-arm exists, we assume the private rust compiler for arm is installed
            InstallWinArmPrivateRustCompiler
        }
    }
    elseif ($Arm64) {
        if (-not (Test-Path 'rust-windows-arm64')) {
            # if the folder rust-windows-arm exists, we assume the private rust compiler for arm is installed
            InstallWinArmPrivateRustCompiler -Arm64
        }
    }
    elseif (-not (Test-RustUp)) {
        Write-Host "Installing rustup and stable-x86_64-pc-windows-msvc Rust."
        Invoke-RestMethod -usebasicparsing 'https://static.rust-lang.org/rustup/dist/i686-pc-windows-gnu/rustup-init.exe' -outfile 'rustup-init.exe'
        if ($LastExitCode)
        {
            Throw "Failed to download rustup with exit code $LastExitCode"
        }

        Write-Host "Running rustup-init.exe"
        ./rustup-init.exe -y --default-toolchain stable-x86_64-pc-windows-msvc
        if ($LastExitCode)
        {
            Throw "Failed to install rust with exit code $LastExitCode"
        }
    }
    else {
        Write-Host "Running rustup.exe"
        rustup install stable-x86_64-pc-windows-msvc
        if ($LastExitCode)
        {
            Throw "Failed to install rust with exit code $LastExitCode"
        }
    }
    
    $ErrorActionPreference = 'Stop'
}

function InstallWinArmPrivateRustCompiler
{
    param (
        [switch] $Arm64
    )
 
    #default arm binaries
    $link = 'https://edgebuild.blob.core.windows.net/iotedge-win-arm32v7-tools/rust-windows-arm.zip'
    $zipFilePath = "rust-windows-arm"
    $destinationFolderPath = "rust-windows-arm"

    if($Arm64)
    {
        # todo:mohan link needs to be updated once zip file uploaded to the blob storage
        $link = '\\scratch2\scratch\mdatla\iotedge-windows-arm64-tools\rust-windows-arm64.zip'
        $zipFilePath = "rust-windows-arm64.zip"
        $destinationFolderPath = "rust-windows-arm64"
    }

    Write-Host "Downloading $link"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest $link -OutFile $zipFilePath -UseBasicParsing

    Write-Host "Extracting $link"
    Expand-Archive -Path $zipFilePath -DestinationPath $destinationFolderPath
    $ProgressPreference = 'Stop'
}

# arm build has to use a few private forks of dependencies instead of the public ones, in order to to this, we have to 
# 1. append a [patch] section in cargo.toml to use crate forks
# 2. run cargo update commands to force update cargo.lock to use the forked crates
# 3 (optional). when building openssl-sys, cl.exe is called to expand a c file, we need to put the hostx64\x64 cl.exe folder to PATH so cl.exe can be found
#   this is optional because when building iotedge-diagnostics project, openssl is not required
function PatchRustForArm {
    param (
        [switch] $OpenSSL,
        [switch] $Arm64
    )

    $vsPath = Join-Path -Path ${env:ProgramFiles(x86)} -ChildPath 'Microsoft Visual Studio'
    Write-Host $vsPath

    # arm build requires cl.exe from vc tools to expand a c file for openssl-sys, append x64-x64 cl.exe folder to PATH
    if ($OpenSSL) {
        try {
            Get-Command cl.exe -ErrorAction Stop
        }
        catch {
            $cls = Get-ChildItem -Path $vsPath -Filter cl.exe -Recurse -ErrorAction Continue -Force | Sort-Object -Property DirectoryName -Descending
            $clPath = ''
            for ($i = 0; $i -lt $cls.length; $i++) {
                $cl = $cls[$i]
                Write-Host $cl.DirectoryName
                if ($cl.DirectoryName.ToLower().Contains('hostx64\x64')) {
                    $clPath = $cl.DirectoryName
                    break
                }
            }
            $env:PATH = $clPath + ";" + $env:PATH
            Write-Host $env:PATH
        }

        # test cl.exe command again to make sure we really have it in PATH
        Write-Host $(Get-Command cl.exe).Path
    }

    $ForkedCrates = @"

[patch.crates-io]
iovec = { git = "https://github.com/philipktlin/iovec", branch = "arm" }
mio = { git = "https://github.com/philipktlin/mio", branch = "arm" }
miow = { git = "https://github.com/philipktlin/miow", branch = "arm" }
winapi = { git = "https://github.com/mohandatla/winapi-rs", branch = "arm/v0.3.5" }

[patch."https://github.com/Azure/mio-uds-windows.git"]
mio-uds-windows = { git = "https://github.com/philipktlin/mio-uds-windows.git", branch = "arm" }

"@

    $ManifestPath = Get-Manifest
    Write-Host "Add-Content -Path $ManifestPath -Value $ForkedCrates"
    Add-Content -Path $ManifestPath -Value $ForkedCrates

    if($Arm64) {
        $cargo = Get-CargoCommand -Arm64
    }
    else {
        $cargo = Get-CargoCommand -Arm
    }

    $ErrorActionPreference = 'Continue'

    Write-Host "$cargo update -p winapi:0.3.5 --precise 0.3.5 --manifest-path $ManifestPath"
    Invoke-Expression "$cargo update -p winapi:0.3.5 --precise 0.3.5 --manifest-path $ManifestPath"
    Write-Host "$cargo update -p mio-uds-windows --manifest-path $ManifestPath"
    Invoke-Expression "$cargo update -p mio-uds-windows --manifest-path $ManifestPath"

    $ErrorActionPreference = 'Stop'
}

function ReplacePrivateRustInPath {
    param (
        [switch] $Arm,
        [switch] $Arm64
    )
    Write-Host 'Remove cargo path in user profile from PATH, and add the private arm version to the PATH'

    $oldPath = $env:PATH

    [string[]] $newPaths = $env:PATH -split ';' |
        ?{
            $removePath = $_.Contains('.cargo')
            if ($removePath) {
                Write-Host "$_ is being removed from PATH"
            }
            -not $removePath
        }
    if($Arm) {
        $newPaths += GetPrivateRustPath
    }
    elseif($Arm64) {
        $newPaths += GetPrivateRustPathForArm64
    }
    $env:PATH = $newPaths -join ';'

    $oldPath
}
