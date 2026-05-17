[CmdletBinding()]
param(
    [string]$InstallDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Repo = "akepo225/gh-pr-context"
$ScriptName = "gh-pr-context"
$PythonArtifact = "gh-pr-context.py"
$WrapperName = "gh-pr-context.cmd"
$VersionRef = if ([string]::IsNullOrWhiteSpace($env:GH_PR_CONTEXT_VERSION)) { "master" } else { $env:GH_PR_CONTEXT_VERSION }

function Die {
    param([string]$Message)
    [Console]::Error.WriteLine("error: $Message")
    exit 1
}

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Die "$Name is required but not found on PATH"
    }
}

function Quote-CmdArgument {
    param([string]$Value)
    '"' + ($Value -replace '"', '\"') + '"'
}

function Quote-PowerShellSingleQuotedString {
    param([string]$Value)
    "'" + ($Value -replace "'", "''") + "'"
}

function Test-PathContainsDirectory {
    param(
        [string]$PathValue,
        [string]$Directory
    )

    if ([string]::IsNullOrWhiteSpace($PathValue)) {
        return $false
    }

    $target = [System.IO.Path]::GetFullPath($Directory).TrimEnd('\', '/')
    foreach ($entry in ($PathValue -split ';')) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }
        try {
            $candidate = [System.IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($entry)).TrimEnd('\', '/')
        } catch {
            continue
        }
        if ([StringComparer]::OrdinalIgnoreCase.Equals($candidate, $target)) {
            return $true
        }
    }
    return $false
}

function Test-PythonCandidate {
    param(
        [string]$Command,
        [string[]]$Arguments
    )

    $resolved = Get-Command $Command -ErrorAction SilentlyContinue
    if (-not $resolved -or $resolved.CommandType -ne "Application") {
        return $null
    }

    $probe = "import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)"
    & $Command @Arguments -c $probe *> $null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    $commandPath = if ($resolved.Source) { $resolved.Source } else { $Command }
    [pscustomobject]@{
        Command = $commandPath
        Arguments = $Arguments
    }
}

function Resolve-Python {
    $candidates = @(
        @{ Command = "py"; Arguments = @("-3") },
        @{ Command = "python"; Arguments = @() },
        @{ Command = "python3"; Arguments = @() }
    )

    foreach ($candidate in $candidates) {
        $python = Test-PythonCandidate -Command $candidate.Command -Arguments $candidate.Arguments
        if ($python) {
            return $python
        }
    }

    Die "python 3.11+ is required but was not found as py, python, or python3"
}

if ($VersionRef -notmatch '^[a-zA-Z0-9._/-]+$') {
    Die "invalid GH_PR_CONTEXT_VERSION: $VersionRef"
}

if ([string]::IsNullOrWhiteSpace($env:USERPROFILE)) {
    Die "USERPROFILE is not set"
}

Require-Command "gh"
Require-Command "git"
$Python = Resolve-Python

if (-not [string]::IsNullOrWhiteSpace($env:INSTALL_DIR)) {
    $InstallDir = $env:INSTALL_DIR
} elseif ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Join-Path $env:USERPROFILE ".local\bin"
}

try {
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
} catch {
    Die "failed to create directory: $InstallDir"
}

$RawBase = "https://raw.githubusercontent.com/$Repo/$VersionRef"
$DownloadUrl = "$RawBase/$PythonArtifact"
$PythonPath = Join-Path $InstallDir $PythonArtifact
$WrapperPath = Join-Path $InstallDir $WrapperName
$TempPath = [System.IO.Path]::GetTempFileName()

try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $TempPath -UseBasicParsing | Out-Null
} catch {
    Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
    Die "failed to download $PythonArtifact"
}

try {
    Move-Item -LiteralPath $TempPath -Destination $PythonPath -Force
} catch {
    Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
    Die "failed to write to $PythonPath"
}

$pythonCommand = @($Python.Command) + @($Python.Arguments)
$pythonInvocation = ($pythonCommand | ForEach-Object { Quote-CmdArgument $_ }) -join " "
$wrapper = @(
    "@echo off",
    "setlocal",
    'set "SCRIPT_DIR=%~dp0"',
    'set "SCRIPT=%SCRIPT_DIR%gh-pr-context.py"',
    "$pythonInvocation ""%SCRIPT%"" %*",
    "exit /b %ERRORLEVEL%"
) -join "`r`n"

try {
    Set-Content -LiteralPath $WrapperPath -Value $wrapper -Encoding ASCII
} catch {
    Die "failed to write to $WrapperPath"
}

Write-Output "installed $ScriptName to $WrapperPath"

$installDirOnPath = Test-PathContainsDirectory -PathValue $env:Path -Directory $InstallDir
if (-not $installDirOnPath) {
    $quotedInstallDir = Quote-PowerShellSingleQuotedString $InstallDir
    [Console]::Error.WriteLine("warning: $ScriptName is not on your PATH")
    [Console]::Error.WriteLine("  Add it for future PowerShell prompts by running:")
    [Console]::Error.WriteLine("    [Environment]::SetEnvironmentVariable('Path', $quotedInstallDir + ';' + [Environment]::GetEnvironmentVariable('Path', 'User'), 'User')")
    $env:Path = "$InstallDir;$env:Path"
}

$versionOutput = & $ScriptName --version 2>$null
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($versionOutput)) {
    Die "failed to run $ScriptName --version"
}

Write-Output "verified $versionOutput"
