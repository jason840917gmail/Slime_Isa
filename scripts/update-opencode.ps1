#!/usr/bin/env pwsh

<#
.SYNOPSIS
Updates the globally installed OpenCode package without changing persistent pnpm settings.

.DESCRIPTION
Temporarily enables lifecycle scripts for this PowerShell process, explicitly allows
the opencode-ai postinstall script, installs the newest release allowed by pnpm's
configured minimum release age, and verifies the launcher generated directly under
PNPM_HOME. The package is reinstalled even when its version is unchanged because
OpenCode's postinstall step generates the platform-native executable. The previous
environment setting is restored before the script exits.

.EXAMPLE
.\scripts\update-opencode.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$pnpmCommand = Get-Command pnpm -ErrorAction Stop
$hadIgnoreScriptsOverride = Test-Path -LiteralPath Env:NPM_CONFIG_IGNORE_SCRIPTS
$previousIgnoreScriptsOverride = $env:NPM_CONFIG_IGNORE_SCRIPTS

try {
    # An environment override has higher priority than persistent npm/pnpm config.
    # It applies only to this process and is restored in the finally block.
    $env:NPM_CONFIG_IGNORE_SCRIPTS = 'false'

    $pnpmArguments = @(
        '--allow-build=opencode-ai'
        'add'
        '--global'
        '--force'
        'opencode-ai@latest'
    )

    Write-Host 'Updating OpenCode with its postinstall script explicitly allowed...'
    & $pnpmCommand.Source @pnpmArguments
    if ($LASTEXITCODE -ne 0) {
        throw "pnpm failed with exit code $LASTEXITCODE."
    }

    $pnpmHome = $env:PNPM_HOME
    if ([string]::IsNullOrWhiteSpace($pnpmHome)) {
        $pnpmHome = (& $pnpmCommand.Source bin --global | Select-Object -Last 1).Trim()
    }

    if ([string]::IsNullOrWhiteSpace($pnpmHome)) {
        throw 'Could not determine PNPM_HOME.'
    }

    $launcher = Join-Path $pnpmHome 'opencode.ps1'
    if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) {
        throw "The expected OpenCode launcher was not generated at '$launcher'."
    }

    Write-Host "Verifying the PNPM_HOME launcher: $launcher"
    $installedVersionOutput = & $launcher --version | Select-Object -Last 1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($installedVersionOutput)) {
        throw "OpenCode verification failed with exit code $LASTEXITCODE."
    }
    $installedVersion = $installedVersionOutput.Trim()

    Write-Host "Installed OpenCode version: $installedVersion"
    Write-Host 'OpenCode was updated successfully.'
}
finally {
    if ($hadIgnoreScriptsOverride) {
        $env:NPM_CONFIG_IGNORE_SCRIPTS = $previousIgnoreScriptsOverride
    }
    else {
        Remove-Item -LiteralPath Env:NPM_CONFIG_IGNORE_SCRIPTS -ErrorAction SilentlyContinue
    }

}
