# OneSync Deployment Guide

For IT admins deploying OneSync to fleets via Intune, Group Policy, SCCM, or scripted installation. Covers silent/unattended install switches and how to push tenant-specific `config.json` alongside the install.

## TL;DR

For most fleets, one of:

```cmd
:: Bundle (recommended) - one shot, brings .NET runtime + Dokan + OneSync
OneSyncSetup.exe /install /quiet /norestart /log "%TEMP%\onesync-install.log"
```

```cmd
:: Standalone MSI - install Dokan first, then OneSync, then push config.json
msiexec /i Dokan_x64.msi /qn /norestart /L*v "%TEMP%\dokan-install.log"
msiexec /i OneSync.msi /qn /norestart /L*v "%TEMP%\onesync-install.log"
xcopy /Y config.json "C:\Program Files\OneSync\"
```

Three files are published with every release. **`OneSyncSetup.exe` is the path of least resistance** — use it unless your deployment tooling specifically prefers raw MSIs.

| File | What it is | When to pick it |
|---|---|---|
| `OneSyncSetup.exe` | Burn bundle = Dokan + OneSync MSI + .NET runtime | Default. Works for Intune Win32 apps, scripts, manual installs. |
| `OneSync.msi` | OneSync MSI alone (no Dokan, no .NET) | GPO software installation, SCCM MSI-only deployments, layered images. **Install `Dokan_x64.msi` first.** |
| `Dokan_x64.msi` | Dokan 2.x user-mode filesystem driver | Required dependency for the standalone OneSync.msi. The bundle includes it. |

## Bundle (OneSyncSetup.exe) switches

The bundle uses WiX Burn conventions:

| Switch | Effect |
|---|---|
| `/install` | Install (default action) |
| `/uninstall` | Uninstall |
| `/repair` | Repair an existing install |
| `/modify` | Open the modify UI |
| `/quiet` (or `/q`, `/s`) | Fully silent, no UI |
| `/passive` | Progress bar only, no prompts |
| `/norestart` | Suppress reboot |
| `/log "<path>"` | Write a verbose log to this path |

**Example (Intune Win32 app install command):**
```cmd
OneSyncSetup.exe /install /quiet /norestart /log "%PROGRAMDATA%\OneSync\install.log"
```

**Example (Intune uninstall command):**
```cmd
OneSyncSetup.exe /uninstall /quiet /norestart
```

**Detection rule (Intune):** File path `C:\Program Files\OneSync\OneSync.exe` exists, version >= `1.3.2.0`.

## MSI (OneSync.msi) switches

OneSync.msi follows standard `msiexec` conventions:

| Switch | Effect |
|---|---|
| `/i OneSync.msi` | Install |
| `/x OneSync.msi` *or* `/x {ProductCode}` | Uninstall |
| `/qn` | Fully silent, no UI |
| `/qb` | Basic UI (progress bar only) |
| `/qr` | Reduced UI |
| `/qf` | Full UI (default) |
| `/L*v "<path>"` | Verbose log |
| `/norestart` | Suppress reboot |
| `INSTALLFOLDER="<path>"` | Override install location (default: `C:\Program Files\OneSync`) |
| `REINSTALL=ALL REINSTALLMODE=vomus` | Repair / reinstall on top |

**Example (silent install to custom location):**
```cmd
msiexec /i OneSync.msi /qn /norestart INSTALLFOLDER="D:\Apps\OneSync" /L*v "%TEMP%\onesync.log"
```

**Note:** OneSync.msi does **not** ship the Dokan driver. Install `Dokan_x64.msi` first:
```cmd
msiexec /i Dokan_x64.msi /qn /norestart
```

## Pushing config.json

OneSync's tenant configuration (`tenantId`, `clientId`, `authority`, drive definitions) lives in `C:\Program Files\OneSync\config.json`. The installer ships a placeholder version — you need to replace it with your own.

**Three common patterns:**

### 1. Copy after install (simplest)

```cmd
:: After OneSync.msi or OneSyncSetup.exe runs
xcopy /Y "\\fileserver\OneSync\config.json" "C:\Program Files\OneSync\config.json"
```

### 2. Intune Win32 app with pre/post script

Package OneSyncSetup.exe + config.json together. Use the Win32 app install command:
```cmd
cmd.exe /c "OneSyncSetup.exe /install /quiet /norestart && copy /Y config.json \"C:\Program Files\OneSync\config.json\""
```

### 3. Group Policy Preferences file copy

Deploy OneSync.msi via "Software Installation" GPO, then use Computer Configuration → Preferences → Windows Settings → Files to copy `config.json` to the install folder on next logon.

## Tenant prep checklist

Before deploying to users, ensure you have an Entra ID app registration set up:

1. **Entra admin centre** → App registrations → New registration
2. Name it `OneSync` (or whatever you prefer), single-tenant
3. **Authentication** → "Allow public client flows" → **Yes**
4. **Authentication** → add redirect URI `https://login.microsoftonline.com/common/oauth2/nativeclient` (mobile/desktop apps)
5. **API permissions** → add Microsoft Graph **delegated** permissions:
   - `Files.ReadWrite`
   - `Sites.ReadWrite.All`
   - `offline_access`
   - `User.Read`
6. Grant admin consent
7. Copy the **Application (client) ID** and **Directory (tenant) ID** into your `config.json`

## Update / upgrade

OneSync uses MSI MajorUpgrade — installing a newer version automatically removes the older one. Same command as a fresh install:
```cmd
OneSyncSetup.exe /install /quiet /norestart
```

The user's local hydrated files, pending uploads, and configuration are preserved across upgrades.

## Troubleshooting silent installs

- **Install returns exit 1603**: usually a custom action failed. Check the verbose log (`/L*v`). The most common cause on managed machines is restrictive ACLs on shortcut files — 1.3.1+ includes a defensive CA that handles this, but if you're hitting it on older builds, manually delete `%PUBLIC%\Desktop\OneSync.lnk` before uninstall.
- **Install returns exit 1638**: another version is already installed. Use the bundle's `/install` (it handles upgrades) or uninstall the old version first.
- **Drives don't mount**: check `%LOCALAPPDATA%\OneSync\Logs\*.log` for `Dokan driver is not installed` — usually means the Dokan MSI didn't run. Reinstall via `msiexec /i Dokan_x64.msi /qn`.

## Removal

```cmd
:: Bundle
OneSyncSetup.exe /uninstall /quiet /norestart

:: Or standalone MSI
msiexec /x OneSync.msi /qn /norestart
:: (optional) remove Dokan too if no other software uses it
msiexec /x Dokan_x64.msi /qn /norestart
```

The uninstaller removes the application binaries but leaves `%LOCALAPPDATA%\OneSync\` (user state, logs, pending uploads) intact. To fully purge user state too, delete that folder after uninstall.

## Questions

Open an issue at https://github.com/madeyouclickstudio/OneSync.
