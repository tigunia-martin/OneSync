# OneSync

A lightweight Windows drive-letter sync client for OneDrive and SharePoint, built for organisations (schools, in particular) that want file-server-style UX on top of Microsoft 365 without running the Microsoft OneDrive sync client.

OneSync mounts OneDrive and SharePoint libraries as native Windows drive letters (e.g. `H:` for personal OneDrive, `I:` and `J:` for shared SharePoint libraries) using a user-mode filesystem driver. Files appear instantly as placeholders; the bytes are fetched only when the user opens them. Folder contents load on demand the first time a user navigates into them, so first-mount is cheap regardless of how big the underlying library is.

## Why OneSync instead of OneDrive sync client?

- **Drive letters, not user-profile folders.** Network-drive style (`H:`, `I:`, `J:`) matches the mental model schools have used for decades. No retraining users to navigate `%USERPROFILE%\OneDrive — Tenant`.
- **Multi-library out of the box.** Mount any number of SharePoint document libraries alongside OneDrive without per-user sync-pair fiddling.
- **Bounded local footprint.** Session-cache mode wipes the placeholder metadata on graceful shutdown so persistent staff profiles never accumulate gigabytes of sync state. Hydrated file content and pending uploads survive the wipe.
- **Lazy-by-default.** No initial /delta walk storm at mount. Folder enumerations happen only when the user opens that folder. First-time login on a fresh machine costs a handful of small Graph requests, not thousands.
- **Cross-machine pending uploads.** Pending uploads are mirrored to a per-user manifest file in OneDrive itself. If a staff member moves between machines with unsent edits on the previous PC, the new PC pops a tray notification telling them where to go finish the upload.
- **Office co-authoring.** Double-clicking an Office document opens it directly via the SharePoint URL (`ms-excel:ofe|u|…`), so AutoSave and real-time co-authoring work the same as opening from the web.

## What it is not

- Not an enterprise-grade replacement for OneDrive sync at FAANG-scale tenant counts. Intended for a single school or small organisation (low hundreds of concurrent users).
- Not for offline-first workflows where users routinely lose network connectivity. OneSync assumes connectivity is the normal state; offline edits queue and resync when connectivity returns, but the user experience is optimised for online use.
- Not a Microsoft product, not endorsed by Microsoft. Uses the documented Microsoft Graph API.

## Requirements

- Windows 10 (1809) or Windows 11
- Local administrator rights to install (kernel-mode Dokan driver)
- A Microsoft 365 tenant with at least one Entra app registration (see Configuration below)
- The bundled installer brings: .NET 8 runtime (self-contained), Dokan 2.x driver, OneSync.exe

## Install

Grab the latest `OneSyncSetup.exe` from the [Releases page](../../releases) and run it. The bundle handles the .NET runtime, Dokan driver, and OneSync MSI in one shot.

For a tenant deployment, see `docs/deployment.md` for the typical Intune / Group Policy flow.

## Configuration

Configuration lives in `config.json` next to `OneSync.exe` (default: `C:\Program Files\OneSync\config.json`). The repo ships:

- `src/OneSync/config.json` — placeholder values, safe defaults for a sanity-check build
- `src/OneSync/config.template.json` — fully-commented reference of every setting

Minimum you have to fill in:

```json
{
  "tenantId": "your-tenant-guid",
  "clientId": "your-app-registration-guid",
  "authority": "https://login.microsoftonline.com/your-tenant-guid",
  "drives": [
    { "letter": "H", "label": "Home", "type": "onedrive", "remotePath": "/" }
  ]
}
```

The Entra app registration needs delegated permissions: `Files.ReadWrite`, `Sites.ReadWrite.All`, `offline_access`, `User.Read`, and must allow public client flows.

## Build from source

```powershell
# Prerequisites: .NET 8 SDK, WiX 6 CLI, Visual Studio Build Tools (for the ShellOverlay C++ project)
cd src\OneSync.Installer
.\build.ps1
```

Output: `OneSync.msi` in the installer folder, plus `dist\OneSyncSetup.exe` (the Burn bundle wrapping the MSI + Dokan driver).

## Architecture sketch

```
  Explorer / app
       │  ReadFile / FindFiles
       ▼
  ┌─────────────┐
  │   Dokan     │  user-mode filesystem
  └─────────────┘
       │
       ▼
  ┌─────────────────────────────────────────────────┐
  │  OneSync.exe                                    │
  │  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
  │  │ Lazy     │  │ Hydration│  │ Delta poller  │  │
  │  │ fallback │  │ on read  │  │ (incremental) │  │
  │  └──────────┘  └──────────┘  └───────────────┘  │
  │  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
  │  │ Upload   │  │ Metadata │  │ Pending       │  │
  │  │ worker   │  │ cache    │  │ manifest      │  │
  │  └──────────┘  └──────────┘  └───────────────┘  │
  └─────────────────────────────────────────────────┘
       │  Graph requests (rate-limited, leaky-bucket)
       ▼
  Microsoft Graph
```

Key choices:
- **LiteDB** for local metadata + sync queue (single-file, no service, embedded)
- **MSAL with WAM broker** for SSO under domain accounts
- **Token bucket** rate limiting (30 req/s sustained, 60 burst by default) so a single user can't accidentally throttle the tenant
- **Session-cache mode** wipes per-user metadata each graceful shutdown to bound disk footprint on persistent profiles

## Security

- All Graph traffic is HTTPS to `graph.microsoft.com`.
- MSAL token cache is per-user, encrypted at rest via DPAPI.
- No telemetry. OneSync makes no outbound network requests other than to Microsoft Graph using the signed-in user's delegated permissions.
- Found a security issue? See [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE). Use it, fork it, modify it, ship it. No warranty.

## Status

Used in production at a single school of ~600 students + staff. Active development; expect occasional breaking config-schema changes between minor versions until 2.0.

See [BACKLOG.md](BACKLOG.md) for known limitations and planned work.
