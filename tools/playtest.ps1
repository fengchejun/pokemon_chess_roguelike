param(
	[ValidateSet("Play", "Editor", "Test")]
	[string]$Mode = "Play",
	[switch]$Clean,
	[string]$Filter = "",
	[string]$GodotExe = "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
)

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$artifactRoot = Join-Path $projectRoot "artifacts"
$profileRoot = Join-Path $artifactRoot "playtest-user"
$roamingRoot = Join-Path $profileRoot "Roaming"
$localRoot = Join-Path $profileRoot "Local"
$logRoot = Join-Path $profileRoot "Logs"

if ($Clean) {
	$profileFull = [System.IO.Path]::GetFullPath($profileRoot)
	$artifactPrefix = [System.IO.Path]::GetFullPath($artifactRoot).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
	if (-not $profileFull.StartsWith($artifactPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
		throw "Refusing to clean a playtest directory outside the project artifacts folder: $profileFull"
	}
	if (Test-Path -LiteralPath $profileFull) {
		Remove-Item -LiteralPath $profileFull -Recurse -Force
	}
}

if (-not (Test-Path -LiteralPath $GodotExe)) {
	$godotCommand = Get-Command godot -ErrorAction SilentlyContinue
	if ($null -eq $godotCommand) {
		throw "Godot executable not found. Pass -GodotExe <path>."
	}
	$GodotExe = $godotCommand.Source
}

$directories = @($roamingRoot, $localRoot, $logRoot)
New-Item -ItemType Directory -Force -Path $directories | Out-Null

# Godot on Windows resolves user:// from APPDATA. Scope the override to this script process and its children.
$env:APPDATA = $roamingRoot
$env:LOCALAPPDATA = $localRoot

if ($Mode -eq "Test") {
	$testArgs = @("--headless", "--path", $projectRoot, "--script", "res://tests/run_all.gd")
	if (-not [string]::IsNullOrWhiteSpace($Filter)) {
		$testArgs += @("--", $Filter)
	}
	& $GodotExe @testArgs
	exit $LASTEXITCODE
}

$logFile = Join-Path $logRoot "game.log"
$launchArgs = @(
	"--path", ('"{0}"' -f $projectRoot),
	"--log-file", ('"{0}"' -f $logFile)
)
if ($Mode -eq "Editor") {
	$launchArgs += "--editor"
}

$process = Start-Process -FilePath $GodotExe -ArgumentList $launchArgs -WorkingDirectory $projectRoot -PassThru
Write-Host "Mode: $Mode"
Write-Host "Profile: $profileRoot"
Write-Host "Log: $logFile"
Write-Host "PID: $($process.Id)"
