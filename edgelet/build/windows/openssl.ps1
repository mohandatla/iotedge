# Copyright (c) Microsoft. All rights reserved.

function Get-OpenSSL
{
    param (
        [switch] $Arm,
        [switch] $Arm64
    )

    $ErrorActionPreference = 'Continue'

    if (!((Test-Path -Path $env:HOMEDRIVE\vcpkg) -and ((Test-Path -Path $env:HOMEDRIVE\vcpkg\vcpkg.exe))))
    {
        Write-Host "Installing vcpkg from github..."
        git clone https://github.com/Microsoft/vcpkg $env:HOMEDRIVE\vcpkg
        if ($LastExitCode)
        {
            Throw "Failed to clone vcpkg repo with exit code $LastExitCode"
        }
        Write-Host "Bootstrapping vcpkg..."
        & "$env:HOMEDRIVE\vcpkg\bootstrap-vcpkg.bat"
        if ($LastExitCode)
        {
            Throw "Failed to bootstrap vcpkg with exit code $LastExitCode"
        }
        Write-Host "Installing vcpkg..."
        & $env:HOMEDRIVE\\vcpkg\\vcpkg.exe integrate install
        if ($LastExitCode)
        {
            Throw "Failed to install vcpkg with exit code $LastExitCode"
        }
    }

    Write-Host "Downloading strawberry perl"
    if (!(Test-Path -Path $env:HOMEDRIVE\vcpkg\Downloads))
    {
        New-Item -Type Directory "$env:HOMEDRIVE\vcpkg\Downloads" | Out-Null
    }

    $strawberryPerlUri = "https://edgebuild.blob.core.windows.net/strawberry-perl/strawberry-perl-5.24.1.1-32bit-portable.zip"
    $strawberryPerlPath = "$env:HOMEDRIVE\vcpkg\Downloads\strawberry-perl-5.24.1.1-32bit-portable.zip"
    Invoke-WebRequest -Uri $strawberryPerlUri -OutFile $strawberryPerlPath

	$architecture = 'x64'
	$packageName = 'openssl:x64-windows'

	if($Arm)
	{
		$architecture = 'arm'
		$packageName = 'openssl-windows:arm-windows'
	}
	else if($Arm64)
	{
		$architecture = 'arm64'
		$packageName = 'openssl-windows:arm64-windows'
	}

    Write-Host "Installing OpenSSL for $architecture..."
    & $env:HOMEDRIVE\vcpkg\vcpkg.exe install $packageName
    if ($LastExitCode)
    {
        Throw "Failed to install openssl vcpkg with exit code $LastExitCode"
    }

    Write-Host "Setting env variables OPENSSL_ROOT_DIR and OPENSSL_DIR..."
    if ((Test-Path env:TF_BUILD) -and ($env:TF_BUILD -eq $true))
    {
        # When executing within TF (VSTS) environment, install the env variable
        # such that all follow up build tasks have visibility of the env variable
        Write-Host "VSTS installation detected"
        Write-Host "##vso[task.setvariable variable=OPENSSL_ROOT_DIR;]$env:HOMEDRIVE\vcpkg\installed\$architecture-windows"
        # Rust's openssl-sys crate needs this environment set.
        Write-Host "##vso[task.setvariable variable=OPENSSL_DIR;]$env:HOMEDRIVE\vcpkg\installed\$architecture-windows"
    }
    else
    {
        # for local installation, set the env variable within the USER scope
        Write-Host "Local installation detected"
        [System.Environment]::SetEnvironmentVariable("OPENSSL_ROOT_DIR", "$env:HOMEDRIVE\vcpkg\installed\$architecture-windows", [System.EnvironmentVariableTarget]::User)
        [System.Environment]::SetEnvironmentVariable("OPENSSL_DIR", "$env:HOMEDRIVE\vcpkg\installed\$architecture-windows", [System.EnvironmentVariableTarget]::User)
    }

    $ErrorActionPreference = 'Stop'
}
