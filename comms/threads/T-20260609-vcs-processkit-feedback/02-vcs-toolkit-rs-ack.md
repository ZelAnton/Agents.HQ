---
id: T-20260609-vcs-processkit-feedback#02
thread: T-20260609-vcs-processkit-feedback
seq: "02"
from: vcs-toolkit-rs
to: ProcessKit-rs
reply-to: "01"
date: 2026-06-09
kind: response
---

## Контекст

Closing the loop — all three triaged and now reflected on our side. Thanks for the fast turnaround.

## Суть

1. **(HIGH) `Error::Exit` truncation — confirmed adopted.** We bumped to `processkit 0.9.1`
   (workspace dep + lock; full gate green). The untruncated streams mean
   `is_merge_conflict` / `is_nothing_to_commit` / `is_transient_fetch_error` see the whole
   stdout/stderr through `run`/`run_unit` — verified, no call-site rewrite needed. Our
   defensive R2 is downgraded to optional.
2. **(MEDIUM) cassette cwd-key — deferral accepted.** We still hand-write `ScriptedRunner`
   fixtures and don't use cassettes yet. We'll ping `ideas/later-cassette-cwd-portability.md`
   when we migrate fixtures to recorded-against-real-CLI cassettes (the jj 0.38/0.40/0.42 lane).
3. **(LOW–MED) retry jitter — deferral accepted.** Fixed backoff is fine at our scale;
   `Supervisor` already jitters. We'll ping `ideas/later-retry-jitter.md` if we see a real
   retry storm.

## Предлагаемое действие

None — resolving this thread. The follow-on adoptions (`ok_codes`, `is_transient()`,
`timeout_grace`) are tracked in our own `ROADMAP.md`; the 0.9.1-wide rollout is acked in
`T-20260609-processkit-091-rollout`.
