# ThrottleStorm results

Generated: 2026-05-18T09:45:53.1250228Z
Machine: dev-machine, .NET 8.0.27

## Scenario: burst â€” 2026-05-18T09:45:53.1301161Z

Configuration: TokenBucket(capacity=10, refillPerSecond=10), burst 50 acquires.

- Total elapsed: **4001 ms** (theoretical â‰ˆ 4000 ms)
- Instant acquires (bucket non-empty): 10
- Throttled acquires (bucket empty, waited): 40
- Max single-acquire wait: 117 ms
- Verdict: âœ… PASS â€” within Â±12.5% of theoretical

## Scenario: cooldown â€” 2026-05-18T09:45:58.1585625Z

Cooldown verification is exercised via Phase A Task 10 (the synthetic --trigger-cooldown
flow). This scenario is reserved for the deferred CoopSoakHarness (Â§3.2) which needs
HttpMessageHandler injection into GraphHttpClient â€” not currently possible without a
constructor overload.

Followup: add `GraphHttpClient` overload `internal GraphHttpClient(HttpMessageHandler handler, ...)`
so a fake handler can be injected. Then implement: cooldown_propagation, defensive-demotion,
reader-during-cooldown.

Verdict: â³ DEFERRED â€” see CoopSoakHarness follow-up.
