# OneSync

A lightweight Windows drive-letter sync client for OneDrive and SharePoint, built for organisations (schools, in particular) that want file-server-style UX on top of Microsoft 365 without running the Microsoft OneDrive sync client — and for those who don't want to pay for Cloud Drive Mapper, don't need an enterprise application solution, and want the features we've added on top (accurate folder sizes in Explorer, working image thumbnail previews, a live upload/sync widget, an in-app Recycle Bin viewer, and more).

OneSync mounts OneDrive and SharePoint libraries as native Windows drive letters (e.g. `H:` for personal OneDrive, `I:` and `J:` for shared SharePoint libraries). Files appear instantly as placeholders; the bytes are fetched only when a user opens them. Folder contents load on demand the first time a user navigates into them, so first-mount is cheap regardless of how big the underlying library is.

## Download

Latest installer: see the [Releases page](../../releases). Three files are published with each release:

- **`OneSyncSetup.exe`** — most users start here. One-shot bundle that brings the .NET 8 runtime, Dokan 2.x driver, and OneSync MSI.
- **`OneSync.msi`** — for IT admins deploying via Intune / GPO / SCCM as a raw MSI. Install `Dokan_x64.msi` first.
- **`Dokan_x64.msi`** — the Dokan user-mode filesystem driver. Required dependency for the standalone MSI; included in the bundle.

Requires local administrator rights (the Dokan filesystem driver is kernel-mode).

For unattended / fleet deployment with silent install switches and tenant configuration, see [DEPLOYMENT.md](DEPLOYMENT.md).

## Inspiration & credits

OneSync wouldn't exist without two commercial tools that pioneered the drive-letter-for-cloud-storage approach:

- **[Cloud Drive Mapper](https://www.iamcloud.com/cloud-drive-mapper-overview/)** by IAMCloud — the gold standard in this space, particularly for large enterprise and multi-site education estates. If you're running thousands of seats across multiple tenants with complex governance requirements, their product is the right fit. Their work proved the model and shaped a lot of the UX expectations users now have.
- **[ZeeDrive](https://www.zeedrive.com/)** — another well-built take on the same idea, lighter touch and great for smaller deployments.

OneSync is a free alternative aimed at the gap between "I want this UX" and "I can justify a per-seat commercial licence." It's the right pick when your org is too small or budget-constrained for a paid product, but the OneDrive sync client is the wrong shape for your users.

## What OneSync adds on top

Most of these came from running similar tools in production at a single school and finding rough edges that mattered to end users. They're not criticisms of the commercial products — they're problems we hit and chose to spend time on:

- **Accurate free-space in File Explorer.** Right-clicking a drive shows the real OneDrive / SharePoint quota and remaining bytes (refreshed periodically via Graph), not a synthetic placeholder. Users actually know when they're about to run out.
- **Image thumbnail previews.** JPG / PNG / HEIC thumbnails render in Explorer the same way they do on a local disk, without the user having to open the file first.
- **Live upload / sync status widget.** A floating tray modal shows in-progress uploads, deletes, and conflict resolutions with percentage and filename, so users can tell at a glance whether their save has actually made it to the cloud.
- **Web Recycle Bin viewer.** Right-click the tray icon → "Recycle Bin" opens an in-app view of the OneDrive / SharePoint recycle bin so users can restore deleted files without leaving the desktop.
- **Recycle-bin desktop icon stays clean.** The OneDrive Recycle Bin folder is excluded from the delta sync, so the local desktop Recycle Bin icon never flips to the "items present" state because of cloud-side deletes the user doesn't care about.
- **Cross-machine pending-upload notification.** If a staff member leaves work-in-progress on one PC and signs into another, a tray balloon on the new machine tells them which files are still pending on which device.

## Why OneSync instead of OneDrive sync client?

- **Drive letters, not user-profile folders.** Network-drive style (`H:`, `I:`, `J:`) matches the mental model schools have used for decades. No retraining users to navigate `%USERPROFILE%\OneDrive — Tenant`.
- **Multi-library out of the box.** Mount any number of SharePoint document libraries alongside OneDrive without per-user sync-pair fiddling.
- **Bounded local footprint.** Session-cache mode wipes the placeholder metadata on graceful shutdown so persistent staff profiles never accumulate gigabytes of sync state. Hydrated file content and pending uploads survive the wipe.
- **Lazy-by-default.** No initial folder-walk storm at mount. Folder enumerations happen only when the user opens that folder. First-time login on a fresh machine costs a handful of small Graph requests, not thousands.
- **Office co-authoring.** Double-clicking an Office document opens it directly via the SharePoint URL, so AutoSave and real-time co-authoring work the same as opening from the web.

## What it is not

- Not an enterprise-grade replacement for OneDrive sync at FAANG-scale tenant counts. Intended for a single school or small organisation (low hundreds of concurrent users). For larger or more complex deployments, look at Cloud Drive Mapper.
- Not for offline-first workflows where users routinely lose network connectivity. OneSync assumes connectivity is the normal state; offline edits queue and resync when connectivity returns, but the UX is optimised for online use.
- Not a Microsoft product, not endorsed by Microsoft. Uses the documented Microsoft Graph API.

## Requirements

- Windows 10 (1809) or Windows 11
- Local administrator rights to install (kernel-mode Dokan driver)
- A Microsoft 365 tenant with at least one Entra app registration (see Configuration below)

## Configuration

Configuration lives in `config.json` next to `OneSync.exe` (default: `C:\Program Files\OneSync\config.json`). [`config.template.json`](config.template.json) in this repo is a fully-commented reference of every setting.

The minimum you have to set:

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

## Security

- All traffic goes over HTTPS to `graph.microsoft.com`.
- MSAL token cache is per-user, encrypted at rest via Windows DPAPI.
- No telemetry. OneSync makes no outbound network requests other than to Microsoft Graph using the signed-in user's delegated permissions.
- Found a security issue? See [SECURITY.md](SECURITY.md).

## License

[Freeware](LICENSE) — free for personal and commercial use, redistribute the unmodified installer, don't resell or repackage. Source code is not provided.
