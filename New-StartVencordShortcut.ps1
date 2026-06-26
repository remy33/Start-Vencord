[CmdletBinding()]
param(
    [string]$ShortcutName = "Start Vencord"
)

$targetScript = Join-Path $PSScriptRoot "Start-Vencord.ps1"

if (-not (Test-Path -LiteralPath $targetScript -PathType Leaf)) {
    Write-Error "Could not find Start-Vencord.ps1 next to this shortcut creator script."
    exit 1
}

$desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
if (-not $desktopPath) {
    Write-Error "Could not find the Windows Desktop path for the current user."
    exit 1
}

$shortcutPath = Join-Path $desktopPath "$ShortcutName.lnk"
$powershellPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$discordBase = Join-Path $env:LOCALAPPDATA "Discord"

if (-not (Test-Path -LiteralPath $powershellPath -PathType Leaf)) {
    $powershellCommand = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $powershellCommand) {
        Write-Error "Could not find powershell.exe."
        exit 1
    }

    $powershellPath = $powershellCommand.Source
}

function Get-LatestDiscordExe {
    param([string]$BasePath)

    if (-not (Test-Path -LiteralPath $BasePath -PathType Container)) {
        return $null
    }

    $appDirs = @(Get-ChildItem -LiteralPath $BasePath -Directory -Filter "app-*" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^app-\d+(\.\d+)+$' } |
        Sort-Object { [version]($_.Name -replace '^app-', '') } -Descending)

    foreach ($appDir in $appDirs) {
        $discordExe = Join-Path $appDir.FullName "Discord.exe"
        if (Test-Path -LiteralPath $discordExe -PathType Leaf) {
            return $discordExe
        }
    }

    return $null
}

$iconPath = Get-LatestDiscordExe -BasePath $discordBase
if (-not $iconPath) {
    $iconPath = $powershellPath
}

$quotedScriptPath = '"' + $targetScript + '"'
$shortcutShell = New-Object -ComObject WScript.Shell
$shortcut = $shortcutShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershellPath
$shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -File $quotedScriptPath"
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = "$iconPath,0"
$shortcut.Description = "Start Vencord and launch Discord"
$shortcut.Save()

Write-Output "Created desktop shortcut: $shortcutPath"
Write-Output "Shortcut icon: $iconPath"
