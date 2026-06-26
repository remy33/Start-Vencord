$link = "https://github.com/Vencord/Installer/releases/latest/download/VencordInstallerCli.exe"
$outfile = Join-Path $env:TEMP "VencordInstallerCli.exe"
$discordBase = Join-Path $env:LOCALAPPDATA "Discord"

function Enable-ModernTls {
    $protocols = [Net.ServicePointManager]::SecurityProtocol

    foreach ($protocolName in @("Tls12", "Tls13")) {
        try {
            $protocol = [Net.SecurityProtocolType]::$protocolName
            $protocols = $protocols -bor $protocol
        }
        catch {
            # Older .NET versions do not know every modern protocol name.
        }
    }

    # TLS 1.2 is value 3072 even when the enum name is missing on older systems.
    $protocols = $protocols -bor [Net.SecurityProtocolType]3072
    [Net.ServicePointManager]::SecurityProtocol = $protocols
}

function Save-UrlToFile {
    param(
        [string]$Uri,
        [string]$OutFile
    )

    Enable-ModernTls
    $downloadErrors = @()

    try {
        Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop
        return
    }
    catch {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        $downloadErrors += "PowerShell Invoke-WebRequest failed: $($_.Exception.Message)"
    }

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        try {
            $curlOutput = & $curl.Source -L --fail --silent --show-error --output $OutFile $Uri 2>&1
            if ($LASTEXITCODE -eq 0) {
                return
            }

            throw "curl.exe exited with code $LASTEXITCODE. $curlOutput"
        }
        catch {
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            $downloadErrors += "curl.exe failed: $($_.Exception.Message)"
        }
    }
    else {
        $downloadErrors += "curl.exe was not found."
    }

    $bits = Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue
    if ($bits) {
        try {
            Start-BitsTransfer -Source $Uri -Destination $OutFile -ErrorAction Stop
            return
        }
        catch {
            Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
            $downloadErrors += "BITS failed: $($_.Exception.Message)"
        }
    }
    else {
        $downloadErrors += "Start-BitsTransfer was not found."
    }

    throw ($downloadErrors -join " ")
}

function Exit-WithErrorPause {
    param(
        [string]$Message,
        [int]$Code = 1
    )

    Write-Error $Message
    Write-Output ""
    Write-Output "A problem occurred. Press any key to exit..."

    try {
        [console]::ReadKey($true) | Out-Null
    }
    catch {
        # If there is no interactive console, briefly delay before exiting.
        Start-Sleep -Seconds 5
    }

    exit $Code
}

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-DiscordAppDirs {
    param([string]$BasePath)

    if (-not (Test-Path $BasePath)) {
        return @()
    }

    return @(Get-ChildItem -Path $BasePath -Directory -Filter "app-*" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^app-\d+(\.\d+)+$' } |
        Sort-Object { [version]($_.Name -replace '^app-', '') })
}

function Get-LatestDiscordAppDir {
    param([string]$BasePath)

    $appDirs = Get-DiscordAppDirs -BasePath $BasePath
    $ordered = @($appDirs | Sort-Object { [version]($_.Name -replace '^app-', '') } -Descending)

    foreach ($dir in $ordered) {
        $resourcesDir = Join-Path $dir.FullName "resources"
        if (Test-Path $resourcesDir) {
            return $dir
        }
    }

    return $null
}

function Test-DiscordBaseInstallLocation {
    param([string]$BasePath)

    if (-not $BasePath) {
        return $false
    }

    $updateExe = Join-Path $BasePath "Update.exe"
    if (-not (Test-Path $updateExe)) {
        return $false
    }

    return $null -ne (Get-LatestDiscordAppDir -BasePath $BasePath)
}

function Repair-LatestDiscordAsar {
    param([string]$BasePath)

    $minimumAsarBytes = 1MB
    $latest = Get-LatestDiscordAppDir -BasePath $BasePath
    if (-not $latest) {
        return $null
    }

    $appAsarPath = Join-Path $latest.FullName "resources\app.asar"
    if (Test-Path $appAsarPath) {
        return $BasePath
    }

    $backupAsarPath = Join-Path $latest.FullName "resources\_app.asar"
    if (-not (Test-Path $backupAsarPath)) {
        Write-Warning "Latest Discord app folder ($($latest.Name)) is missing both app.asar and _app.asar."
        return $null
    }

    $backupSize = (Get-Item $backupAsarPath).Length
    if ($backupSize -lt $minimumAsarBytes) {
        Write-Warning "Latest Discord backup asar is unexpectedly small ($backupSize bytes)."
        return $null
    }

    Write-Warning "Latest Discord app folder ($($latest.Name)) is missing app.asar. Attempting restore from _app.asar in the same version."
    try {
        Copy-Item -LiteralPath $backupAsarPath -Destination $appAsarPath -Force -ErrorAction Stop
        Write-Output "Restored missing app.asar in $($latest.Name) from $backupAsarPath."
    }
    catch {
        Write-Warning "Failed to restore missing app.asar in $($latest.Name): $_"
        return $null
    }

    if (Test-Path $appAsarPath) {
        return $BasePath
    }

    Write-Warning "Latest Discord app folder ($($latest.Name)) is still missing app.asar after restore."
    return $null
}

function Test-VencordPatchPresent {
    param([string]$ResourcesDir)

    if (-not $ResourcesDir -or -not (Test-Path -LiteralPath $ResourcesDir -PathType Container)) {
        return $false
    }

    $appAsarPath = Join-Path $ResourcesDir "app.asar"
    $backupAsarPath = Join-Path $ResourcesDir "_app.asar"
    $indexJsPath = Join-Path $appAsarPath "index.js"

    if (-not (Test-Path -LiteralPath $backupAsarPath -PathType Leaf)) {
        return $false
    }

    if (Test-Path -LiteralPath $appAsarPath -PathType Container) {
        if (-not (Test-Path -LiteralPath $indexJsPath -PathType Leaf)) {
            return $false
        }

        try {
            $indexJs = Get-Content -LiteralPath $indexJsPath -Raw -ErrorAction Stop
        }
        catch {
            return $false
        }

        return $indexJs -match 'Vencord.*dist.*patcher\.js|require\s*\(.+patcher\.js'
    }

    if (-not (Test-Path -LiteralPath $appAsarPath -PathType Leaf)) {
        return $false
    }

    try {
        $appAsar = Get-Item -LiteralPath $appAsarPath -ErrorAction Stop
        if ($appAsar.Length -gt 64KB) {
            return $false
        }

        $loader = Get-Content -LiteralPath $appAsarPath -Raw -ErrorAction Stop
        return $loader -match 'Vencord.*dist.*patcher\.js'
    }
    catch {
        return $false
    }
}

$discordInstallLocation = $null
$needsRepair = $true
$latestDiscordAppDir = Get-LatestDiscordAppDir -BasePath $discordBase

if ($latestDiscordAppDir) {
    $resourcesDir = Join-Path $latestDiscordAppDir.FullName "resources"
    if (Test-VencordPatchPresent -ResourcesDir $resourcesDir) {
        $discordInstallLocation = $discordBase
        $needsRepair = $false
        Write-Output "Vencord patch already present in $($latestDiscordAppDir.Name). Skipping repair."
    }
    else {
        $discordInstallLocation = Repair-LatestDiscordAsar -BasePath $discordBase

        if ((Test-DiscordBaseInstallLocation -BasePath $discordBase) -and (-not $discordInstallLocation)) {
            Exit-WithErrorPause "Discord's newest app folder is incomplete and app.asar could not be restored. Fully close Discord, wait a few seconds for updates to finish, then run this script again."
        }
    }
}

if ($needsRepair) {
    # Ensure TEMP directory exists
    New-Item -ItemType Directory -Path (Split-Path $outfile) -Force | Out-Null

    # Refresh logic (8 days)
    $refreshDays = 8
    $needsDownload = -not (Test-Path $outfile)

    if (-not $needsDownload) {
        $age = (Get-Date) - (Get-Item $outfile).LastWriteTime
        if ($age.Days -ge $refreshDays) {
            $needsDownload = $true
        }
        else {
            Write-Output "Using cached installer (last downloaded $($age.Days) days ago)."
        }
    }

    # Download installer if needed
    if ($needsDownload) {
        Write-Output "Downloading or refreshing installer..."
        $tmpOutfile = "$outfile.tmp"
        try {
            Save-UrlToFile -Uri $link -OutFile $tmpOutfile

            if (-not (Test-Path $tmpOutfile)) {
                throw "Downloaded installer was not created."
            }

            $downloadedFile = Get-Item $tmpOutfile
            if ($downloadedFile.Length -lt 1MB) {
                throw "Downloaded installer is unexpectedly small ($($downloadedFile.Length) bytes)."
            }

            $stream = [System.IO.File]::OpenRead($tmpOutfile)
            try {
                if ($stream.Length -lt 2) {
                    throw "Downloaded installer is too small to validate."
                }

                $firstByte = $stream.ReadByte()
                $secondByte = $stream.ReadByte()
            }
            finally {
                $stream.Dispose()
            }

            if ($firstByte -ne 0x4D -or $secondByte -ne 0x5A) {
                throw "Downloaded installer does not look like a Windows executable."
            }

            Move-Item -LiteralPath $tmpOutfile -Destination $outfile -Force -ErrorAction Stop
        }
        catch {
            Remove-Item -LiteralPath $tmpOutfile -Force -ErrorAction SilentlyContinue
            Exit-WithErrorPause "Failed to download Vencord installer: $_"
        }
    }

    # Vencord and Discord both recommend not patching from an elevated shell.
    if (Test-IsAdministrator) {
        Write-Warning "This script is running as Administrator. Discord and Vencord patching are more reliable in a normal PowerShell window."
    }

    # Close Discord and its updater process if running
    $discordProc = @(Get-Process Discord -ErrorAction SilentlyContinue)
    $discordUpdateProc = @(Get-Process Update -ErrorAction SilentlyContinue | Where-Object {
            try {
                $_.Path -and $_.Path.StartsWith($discordBase, [System.StringComparison]::OrdinalIgnoreCase)
            }
            catch {
                $false
            }
        })
    $processesToStop = @($discordProc) + @($discordUpdateProc)
    if ($processesToStop) {
        Write-Output "Closing Discord and updater processes..."
        foreach ($proc in @($processesToStop)) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            }
            catch {
                Write-Warning "Could not close $($proc.ProcessName) process $($proc.Id): $($_.Exception.Message)"
            }
        }

        $processIdsToWaitFor = @($processesToStop | Select-Object -ExpandProperty Id)
        Wait-Process -Id $processIdsToWaitFor -Timeout 2 -ErrorAction SilentlyContinue
    }

    # Repair Vencord
    Write-Output "Repairing Vencord (stable)..."
    if (Test-Path $outfile) {
        $installerArgs = @("--repair")
        if ($discordInstallLocation) {
            $installerArgs += @("--location", $discordInstallLocation)
            Write-Output "Targeting Discord install: $discordInstallLocation"
        }
        else {
            $installerArgs += @("--branch", "stable")
        }

        & $outfile @installerArgs

        if ($LASTEXITCODE -ne 0) {
            Exit-WithErrorPause "Vencord installer failed with exit code $LASTEXITCODE." $LASTEXITCODE
        }
    }
    else {
        Exit-WithErrorPause "Installer not found. Cannot repair Vencord."
    }
}

# Launch Discord
$discordUpdate = Join-Path $discordBase "Update.exe"
if (Test-Path $discordUpdate) {
    Write-Output "Launching Discord (Stable)..."
    Start-Process $discordUpdate "--processStart Discord.exe"
}
else {
    Write-Warning "Discord Stable not found."
}

Write-Output ""
Write-Output "Done."
