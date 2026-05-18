# CacheSizeProbe results

Generated: 2026-05-18T10:06:36.3960393Z
Machine: dev-machine, .NET 8.0.27

Synthetic `RemoteItem` list fed through `DeltaCache.BuildPayload` (the same code
path production uses) and serialised with `JsonSerializer.Serialize` +
`DefaultIgnoreCondition = WhenWritingNull` to mirror `DeltaCache.WriteIfChangedAsync`.

Each N is measured TWICE: full cache (maxAgeDays=0) AND sliding-window cache
(maxAgeDays=30). The sliding-window row models actual production behaviour
per the cooperative-polling design (folders always kept, files only if modified
within the window).

Spec exit criteria for the cooperative-polling cache:
- Serialised size at 351k items should be â‰¤ 50 MB.
- Write time at 351k items should be â‰¤ 250 ms.
- If exceeded: ship a streaming/sliding-window variant.

Note: synthetic file `LastModified` is uniform across last 365 days, so the
sliding-window filter (which drops files older than 30 days but keeps every folder)
retains roughly 30/365 â‰ˆ 8% of files. Real-world libraries skew newer, so production
sliding-window size is likely between the two columns below â€” closer to the
sliding-window number for cold libraries, closer to the full-cache number for
actively-edited libraries.

| Items | Folders | Files | Full KB | Sliding KB | Sliding items | Full write (ms) | Sliding write (ms) |
|------:|--------:|------:|--------:|-----------:|--------------:|----------------:|-------------------:|
|   1000 |     700 |   300 |   371.5 |      271.1 |           730 |              43 |                  1 |
|  10000 |    8000 |  2000 |  3712.2 |     3028.7 |          8163 |              17 |                 12 |
| 100000 |   90000 | 10000 | 37108.8 |    33703.3 |         90845 |             134 |                 59 |
| 351000 |  315900 | 35100 | 130251.5 |   118228.6 |        318680 |             236 |                216 |
| 500000 |  450000 | 50000 | 185542.9 |   168464.3 |        454089 |             388 |                314 |
| 1000000 |  900000 | 100000 | 371087.4 |   336977.5 |        908308 |             753 |               1350 |

## Verdict â€” investigated 2026-05-18 follow-up

**FAIL even with sliding window**, at the modelled J:-scale (351k items, 90% folders).

| Threshold | Full cache | Sliding cache (30d) |
|---|---|---|
| 50 MB size gate at 351k | 127 MB â€” **FAIL** (Ã—2.5) | 115 MB â€” **FAIL** (Ã—2.3) |
| 250 ms write gate at 351k | 236 ms â€” borderline PASS | 216 ms â€” PASS |

**Why sliding window doesn't help much:** the J: library is folder-heavy. At a 90/10 folder/file ratio, only ~35k of 351k items are files. Even with a 30-day filter dropping ~92% of those files, only ~32k items get filtered out â€” a ~10% size reduction. Folders dominate the cache; the sliding window's "keep all folders" rule preserves them all.

**Implications:**
- The size gate is the binding constraint, not write time. Write time at 351k under the sliding window is well within budget.
- Shrinking the file window (e.g. 14 days) saves only marginal bytes since files are the small contributor.
- Real production relief options, in order of preference:
  1. **Drop unused fields from `DeltaCacheItem`** (e.g. `WebUrl` is ~100 bytes/item Ã— 350k = ~35 MB â€” gone from the cache, looked up on demand from MetadataStore on the reader side).
  2. **Compact identifiers**: GUID hex (32 chars) â†’ shorter base62 â†’ ~20 char saving per `Id`+`ParentId`+`ETag` Ã— 3 fields Ã— 350k = ~20 MB.
  3. **Gzip-compress the cache payload** before PUTting to Graph; library file content is opaque to Graph, so this is safe. Typical JSON gzip ratio: 5Ã—â€“10Ã— â€” would bring 115 MB down to 12â€“23 MB. **Highest ROI** because no schema change, and gzip is in the BCL.
  4. **Switch to MessagePack/CBOR**: 2Ã—â€“3Ã— smaller than JSON. Lower ROI than gzip and requires both leader + readers to agree on schema bump.
  5. **Page the cache across N files** (`delta-cache-0001.json` â€¦ `delta-cache-NNNN.json`) so individual file size stays manageable. Significantly more complex.

**Caveat â€” the production log line that triggered this investigation doesn't reconcile.** The May 15 log line ("66023 folders + 806 files = 66829 items, **559,936 bytes**") shows ~8 bytes/item, which is mathematically impossible for the serialised shape (a single `"id":"<32-char-guid>"` is already 41 bytes; with name + path + eTag + webUrl the minimum is ~200 bytes per item). Either:
- The log line is misleading (truncated write? partial enumeration? old build before the Items field was populated?), OR
- The production cache uses dramatically shorter identifiers than the probe assumes (e.g. small numeric IDs instead of GUIDs â€” but the code constructs from `RemoteItem.RemoteItemId` which is GUID-shaped).

Worth a manual inspection of `%LOCALAPPDATA%\OneSync\Drives\<library>\.onesync\delta-cache.json` from a real library to settle. Until then, **trust the probe over the log line** â€” the probe uses the actual production code path and produces math-consistent results.

**Recommendation for pilot:** **don't deploy cooperative polling against the J: library** (or any library expected to exceed ~50k items) until either (a) gzip compression is added to `DeltaCache.WriteIfChangedAsync` (a ~30-line BCL-only change), or (b) the 547-KB-vs-118-MB discrepancy is explained by reading a real production cache file. For pilot to a smaller department's library (say <50k items), the sliding-window cache fits comfortably within both gates and is safe to ship as-is.
