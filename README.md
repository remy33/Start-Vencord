# Start Vencord

A small Windows PowerShell helper for repairing Vencord on Discord Stable and launching Discord afterwards.

The project also includes a shortcut creator that places a `Start Vencord` shortcut on your Windows Desktop. The shortcut uses the Discord icon when Discord Stable is installed in the default location.

## Files

- `Start-Vencord.ps1` - downloads or reuses the Vencord CLI installer, repairs Vencord for Discord Stable, then launches Discord.
- `New-StartVencordShortcut.ps1` - creates or updates a Desktop shortcut that runs `Start-Vencord.ps1`.

## Requirements

- Windows
- PowerShell 5.1 or newer
- Discord Stable installed in the default user location:
  `%LOCALAPPDATA%\Discord`
- Internet access the first time the Vencord installer is downloaded

## Usage

Clone or download this repository, then open PowerShell in the project folder.

On Windows 11, you can right-click `Start-Vencord.ps1` and select **Run with PowerShell**.

Run the main script:

```powershell
.\Start-Vencord.ps1
```

Create the Desktop shortcut:

```powershell
.\New-StartVencordShortcut.ps1
```

You can also right-click `New-StartVencordShortcut.ps1` and select **Run with PowerShell** to create the Desktop shortcut.

After the shortcut is created, you can run `Start Vencord` directly from your Desktop.

## What The Script Does

`Start-Vencord.ps1`:

1. Checks whether Vencord already appears to be patched into the latest Discord Stable app folder.
2. Restores Discord's `app.asar` from `_app.asar` if Discord appears partially patched or incomplete.
3. Downloads the latest `VencordInstallerCli.exe` when needed.
4. Reuses the cached installer from `%TEMP%` for up to 8 days.
5. Closes running Discord and Discord updater processes.
6. Runs the Vencord installer in repair mode.
7. Launches Discord Stable.

## Shortcut Icon

`New-StartVencordShortcut.ps1` looks for the newest installed Discord Stable executable at:

```text
%LOCALAPPDATA%\Discord\app-*\Discord.exe
```

If it finds Discord, the Desktop shortcut uses the Discord icon. If it cannot find Discord, it falls back to the PowerShell icon.

## Execution Policy

If PowerShell blocks scripts on your system, you can run this from the project folder:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-Vencord.ps1
```

The Desktop shortcut already uses `-ExecutionPolicy Bypass` for that single script run.

## Notes

- Run this from a normal PowerShell window, not an Administrator window. Discord and Vencord patching are usually more reliable without elevation.
- This script targets Discord Stable only.
- The Vencord installer is downloaded from the official Vencord GitHub releases URL.

## Disclaimer

This is an unofficial helper script. Use it at your own risk.
