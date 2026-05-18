# OneSync — Future Features Backlog

**Status:** Brainstorm — none of these are implemented as of v1.0.8.
**Date:** 2026-05-13
**Context:** Items identified after the core build (Phases 0-13 of v1.0.8) was complete. Listed roughly in order of "would I push back if someone called this scope creep" — top items are no-brainers, bottom items are speculative.

Each item is honest about effort and trade-offs so the next developer (or future me) can make sensible cuts.

---

## Tier 1 — Genuine no-brainers

These are the items I would defend in any review. Combined effort is roughly 6–8 hours and they dramatically reduce support load.

### 1. Diagnostic export from tray menu (~2 hrs)

Right-click tray → **Export diagnostics…** → produces a zip on the desktop containing:
- Last 7 days of Serilog files
- Current `config.json` with tenant/client IDs redacted
- Sync queue snapshot (no file contents, just paths + states)
- Pending manifest snapshot
- Machine info (Windows version, .NET runtime, Dokan version)
- Any crash files (see item 4)

Student emails the zip to IT. Saves the "walk to the classroom" support dance and is the single highest-leverage feature for support load. IT can read everything they need without remote-desktop access.

### 2. Pause / Resume sync (~1 hr)

Tray menu toggle. When paused:
- Delta poller idle (no incoming changes)
- Upload worker idle (no outgoing changes)
- Local watcher continues to record changes for when you resume

Useful for:
- Students on metered mobile hotspot
- Exam silence / no-balloon mode
- Anyone making a big edit without triggering 50 in-flight uploads

Sub-menu: *Pause for 15 min / 1 hour / until tomorrow / indefinitely*. The "until tomorrow" option auto-resumes at next morning, the "indefinitely" option requires explicit resume.

State persists across restarts via a flag in HKCU so paused mode survives a logoff.

### 3. Wider exclude patterns (~15 min)

We already skip `~$*`, `*.tmp`, `Thumbs.db`, `desktop.ini`, `.ds_store`, `*.lnk`. Missing:

- `*.crdownload` — Chrome partial downloads
- `*.part` — Firefox partial downloads
- `*.swp`, `*.swo` — vim swap files
- `*.lock`, `*.lck` — generic lock files
- `~*.tmp` — Office temp files (other than `~$*`)
- `__autosave_*` — JetBrains IDE autosaves
- `WRL*.tmp` — Word recovery temp
- `*.bak.tmp` — generic backup-during-save
- `*.crswap` — Chromium crash swap

Pure config edit; eliminates a long tail of pointless uploads. Update `config.template.json` and the default `ExcludePatterns` list in `AppConfig.cs`.

### 4. Crash dumps for FATAL exceptions (~30 min)

Currently only Serilog captures unhandled exceptions. Add an `AppDomain.UnhandledException` handler that writes a dated file:

```
%LOCALAPPDATA%\OneSync\Crashes\crash-2026-05-13-143052.txt
```

Containing:
- Exception type, message, full stack trace
- Recent log tail (last 200 lines)
- Process info (PID, uptime, working set)
- Currently mounted drives
- Pending queue counts

Diagnostic export (item 1) picks them up. Without this, "the app crashes sometimes" is unfixable.

### 5. Force resync command (~30 min)

Already on the previous deferred list. Tray → **Sync → Force full resync of H:** (one entry per mounted drive). This:
- Clears that drive's delta token in `sync_queue.db`
- Wipes the placeholder metadata for that drive only (preserves other drives)
- Next delta poll does a full re-fetch

Last-resort recovery when sync drifts (placeholder count doesn't match cloud, files missing, etc).

### 6. Local-disk-free safeguard / LRU eviction (~3 hrs)

When `%LOCALAPPDATA%` free space drops below a threshold (default 2 GB, configurable), de-hydrate the least-recently-used files back to placeholders to reclaim space:

- Track `LastAccessedAt` on `RemoteItem` (update in `HydrationService` after hydration, in Dokan ReadFile after subsequent reads)
- Background timer checks disk free every 60 seconds
- When threshold crossed: enumerate hydrated files sorted by `LastAccessedAt` ascending, truncate them back to 0 bytes one by one until we're 1 GB above threshold
- Mark them `CloudOnly` in the overlay

**Crucial for student laptops with 64 GB SSDs.** Without this, every file a student opens uses disk space permanently and we'll get the dreaded "disk full" on shared machines after a few weeks of use. This is non-negotiable for production.

Trade-off: a file the user actively wants offline (taking home, exam revision) might get evicted at an awkward moment. Mitigation: pin files via right-click "Always keep on this device" (item 9, Tier 2).

---

## Tier 2 — Strong arguments either way

### 7. Bandwidth ceiling (~2 hrs)

`maxUploadBytesPerSecond` config knob (optional, 0 = unlimited). Useful for not saturating the school WAN at 8:30 a.m. when 1,500 students log in at once.

Implementation: rate-limit chunks in `UploadWorker.ResumableUploadAsync` via a token-bucket. Simple uploads (<4 MB) skip throttling.

Less critical than the Graph-side throttle backoff we already have (which protects against Microsoft's rate limits, not your WAN), but solves a different problem: school upload pipe saturation.

### 8. OneDrive client coexistence detection (~30 min)

At startup, detect if Microsoft's OneDrive sync client is running (`OneDrive.exe`) and check whether it's pointed at the same tenant. Show a balloon:

> **OneDrive is also running**
> Both apps are syncing the same files — please disable Microsoft OneDrive or OneSync to avoid duplicate uploads and conflicts.

Implementation: check `Get-Process OneDrive` + read its `HKCU\Software\Microsoft\OneDrive\Accounts\Business1\ConfiguredTenantId`. If it matches our tenant, balloon.

Important during the migration window when some students might still have it from previous setups.

### 9. Right-click "Sync now this file" / "Always keep on this device" (~3-4 hrs)

Shell extension `IContextMenu` for files inside our managed drives. Adds menu items:

- **Sync now** — forces upload of THIS file ignoring debounce
- **Always keep on this device** — sets a pin flag in metadata so LRU eviction (item 6) skips it
- **Stop keeping on this device** — opposite of above; immediately de-hydrate

Same C++ project as the overlay DLL — adds a `IContextMenu` COM class. Same registration mechanism.

Standard Windows users expect these from OneDrive — feels missing if they're not there.

### 10. First-run welcome dialog (~1 hr)

Tiny WinForms modal on first launch only:

```
┌────────────────────────────────────────┐
│ Welcome to OneSync          │
├────────────────────────────────────────┤
│ Your H: drive (Home Folder) now syncs  │
│ to OneDrive automatically.             │
│                                        │
│ ☁️ Look for this icon in the system    │
│    tray (bottom-right). Click it for   │
│    status, settings, and help.         │
│                                        │
│ ✅ Files with a green tick are saved   │
│    to OneDrive. Cloud icons mean       │
│    "not yet downloaded".               │
│                                        │
│         [Got it]  [Help]               │
└────────────────────────────────────────┘
```

Click-through saved in `HKCU\Software\OneSync\OneSync\WelcomeShown = 1`. Reduces "what is this thing" support tickets in the first week.

---

## Tier 3 — Worth mentioning, lower priority

### 11. Visual sync queue viewer (~2 hrs)

Tray menu → **Show pending uploads** → small WinForms list window with columns: file path, size, queued at, status, retries. Refresh button. Right-click row → *Force retry / Drop from queue / Open containing folder*.

Useful for debugging more than for users. The diagnostic export already contains the queue snapshot so this is mostly UI polish.

### 12. Auto-update via signed MSI from a URL (~6+ hrs)

Saves IT repeated Intune pushes for minor updates. Significant moving parts:
- Code signing certificate (cost + key management)
- Update host (Azure Blob? Internal server?)
- Update manifest format
- Signature verification on the client
- Rollback handling for bad updates

Lots of risk surface. Probably not worth it for a single-school deployment; high value for multi-tenant SaaS.

### 13. Group Policy ADMX template (~4 hrs)

ADMX/ADML files in Group Policy registry-policy format. Lets IT push the entire `config.json` schema via GPO instead of redeploying the MSI.

High value if OneSync ever ships to other schools (multi-tenant ops); for a single-organization deployment, the current single MSI works.

### 14. Graph search integration (~3 hrs)

Tray menu → **Search files…** → opens a search popup that queries `/me/drive/search(q='...')` and shows results. Click a result → open via Explorer (hydrates on demand).

Useful but underutilised in practice — most users use Explorer's own search (which only sees hydrated files).

### 15. Smart prefetch / predictive hydration

Watch which files the user opens repeatedly and pre-hydrate them at idle time. Sounds clever, in practice gets 80% of the value from just hydrating recently-accessed files on logon (which delta poll already kind of does).

Not worth the complexity until we have real usage data showing what to prefetch.

### 16. "Switch account" for staff

Rare for students (they have one account), occasionally needed for staff who teach across multiple campuses. Tray → **Sign out** clears the MSAL cache; next launch shows the WAM picker.

Already kind of works (the WAM `Prompt.SelectAccount` was set when we were debugging auth) — just no menu item to trigger it.

---

## Migration / coexistence (separate concern)

Worth thinking about as a one-off project before the school-wide rollout:

- **Detect existing CDM install** and surface a warning at install time: *"IAM Cloud Drive Mapper is currently installed. We recommend uninstalling it before using OneSync to avoid drive-letter conflicts."*
- **Migrate folder redirection** from CDM's HKCU keys — back them up before we overwrite, so removing CDM doesn't break the user's Documents pointer.
- **Side-by-side mode** for the first week where OneSync does everything CDM does except sync, and CDM continues to sync. Then flip when confidence is high.

These are deployment-engineering tasks more than feature work — probably 1–2 days of careful scripting and Intune package authoring.

---

## My recommended next sprint

If you (or anyone) come back to this with a few days:

1. Bundle Tier 1 items (#1–#6) into a single PR — they're all small, individually low-risk, collectively very high-leverage. Especially #1 (diagnostic export) and #6 (LRU eviction).
2. Add Tier 2 item #8 (OneDrive coexistence detection) — 30 minutes, prevents the most likely first-week support call.
3. Leave everything else until first deployment generates real complaints. Speculative features have a way of being the wrong features.

Resist the temptation to ship #9 (shell extension menu items) until #6 (LRU eviction) is in — because once LRU evicts a file the user is mid-edit on, you want a "Stop keeping on device" menu item to give them control. Without LRU, the "Always keep" menu has nothing to opt out of.

---

## Things explicitly NOT recommended

A few features have come up in similar contexts that I'd argue against unless there's specific demand:

- **Telemetry / usage analytics.** Privacy red flag in an education setting. If we ever need usage data, do an opt-in survey instead.
- **Cross-tenant support.** "Let users connect personal OneDrive too." Massive scope creep, security concern, no obvious benefit for school deployment.
- **Mobile companion app.** OneDrive mobile already exists. Building our own is pointless.
- **Office file co-authoring.** CDM had this via SyncEngine providers — it was the source of most CDM bugs. Office Online does it well; users should use that.
- **End-to-end encryption.** OneDrive is already encrypted at rest. Adding another layer means our app has the keys, which means key management, which means losing the keys means data loss. Don't.

---

## CoopSoakHarness — deferred from Phase D scale-readiness (2026-05-18)

The cooperative-polling soak test harness (§3.2 of `docs/superpowers/specs/2026-05-18-scale-readiness-design.md`)
was deferred from Phase D because it requires a dedicated test SharePoint library and an
HttpMessageHandler injection point on GraphHttpClient — neither of which is in place.

**To implement when ready:**

1. Provision a test SharePoint library with `controlFolder = ".onesync-test"`. NOT I: or J: — must be safe to wipe.
2. Add an internal `GraphHttpClient` ctor overload accepting an HttpMessageHandler so a fake handler can inject 429s without hitting real Graph.
3. Implement the deferred scenarios (extend `--throttle-storm` or add `tools/CoopSoakHarness/`):
   - Cold start race (10× repeats, exactly one leader)
   - Graceful handoff (kill leader, peer takes over within `leaseTtlSeconds + 30s`)
   - Ungraceful death (force-kill mid-write, ETag-protected takeover)
   - Network partition (block 443 for 5 min, defensive demotion fires at `leaseTtlSeconds / 2`)
   - Concurrent renewal vs takeover (no split-brain)
   - Cooldown propagation (inject 429 on delta-poll, all subsequent block, log fires)
   - Reader during cooldown (inject 429 on cache fetch, reader doesn't crash, view goes stale)

**Why it's safe to defer:** the 50-user pilot on a real shared library IS the cooperative-polling soak test in practice.
Phase A's structured cooldown logging + Phase C's diagnostic export mean any failure during pilot is fully observable.

## Cache-size deeper investigation — Phase D follow-up (2026-05-18) — INVESTIGATED

**Hypothesis 1 (compact format): REJECTED.** Read `DeltaCache.WriteIfChangedAsync`: production uses plain `JsonSerializer.Serialize` with one option (`DefaultIgnoreCondition = WhenWritingNull`). No gzip, no CBOR, no compact format. The probe was using essentially the same serialiser; matching it exactly (with the WhenWritingNull option) didn't change results materially.

**Hypothesis 2 (sliding window): PARTIALLY ACCEPTED but DOESN'T EXPLAIN THE LOG LINE.** The probe was re-run using `DeltaCache.BuildPayload(..., maxAgeDays: 30)` — the actual production code path. Results (full table in `docs/measurements/cache-size-2026-05-18.md`):

| Items | Full cache | Sliding cache (30d) |
|---|---|---|
| 66,829 (modelled May 15) | ~25 MB | ~22 MB |
| 351,000 (current J:) | 127 MB | **115 MB** |

The sliding window saves only ~10% at folder-heavy library shapes because the filter keeps every folder. At 351k items with 90% folders, only ~32k file entries get filtered out.

**The May 15 production log line of 547 KB for 66829 items remains unexplained.** Math says it's impossible: a single `"id":"<32-char-guid>"` is 41 bytes, so 66k items can't fit in 547 KB regardless of which other fields are populated. Either the log line is from a partial enumeration, a truncated write, or an older code path. Cannot resolve without inspecting a real `<library>/.onesync/delta-cache.json` on disk — which requires I: or J: enabled in config and cooperative polling active.

**Verdict at J:-scale: even sliding-window FAILS the 50 MB size gate by 2.3×.** Recommended fix, in order of ROI:
1. **Gzip-compress the cache payload** before PUTting to Graph (~30 lines of BCL-only change in `DeltaCache.WriteIfChangedAsync`; typical JSON gzip ratio brings 115 MB to 12–23 MB).
2. Drop the `WebUrl` field from `DeltaCacheItem` (looks up on demand from MetadataStore on reader side; ~35 MB savings at 350k items).
3. Compact identifiers (GUID hex → base62) for ~20 MB savings.

**Pilot recommendation:** safe for libraries up to ~50k items as-is; **don't deploy cooperative polling against the J: library** until gzip compression ships or the 547-KB-vs-115-MB discrepancy is settled via real-cache-file inspection.

