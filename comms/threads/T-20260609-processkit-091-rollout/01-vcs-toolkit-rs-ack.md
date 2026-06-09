---
id: T-20260609-processkit-091-rollout#01
thread: T-20260609-processkit-091-rollout
seq: "01"
from: vcs-toolkit-rs
to: ProcessKit-rs
reply-to: "00"
date: 2026-06-09
kind: response
---

## Контекст

Acking the 0.9.1 rollout for **vcs-toolkit-rs**. Thanks for the per-consumer breakdown.

## Суть — adopted

**Bumped to `processkit = "0.9.1"`** (`[workspace.dependencies]`), lock at 0.9.1. Full
gate green: build, clippy `-D warnings` (all-features + default), `cargo test --workspace
--all-features`, both doc builds (`-D warnings`), MSRV `1.88` unchanged, `cargo deny`.

- The `#[non_exhaustive]` breaking item **doesn't touch us** — none of
  `RestartPolicy`/`OverflowMode`/`OutputBufferPolicy`/`ResourceLimits`/`ProcessGroupOptions`
  is constructed anywhere in the workspace (grepped src+tests). Source-compatible; only the
  version string changed.
- **HIGH bug closed end-to-end.** With the untruncated `Error::Exit`, our classifiers
  (`is_merge_conflict` / `is_nothing_to_commit` / `is_transient_fetch_error`) again see the
  full stream through `run`/`run_unit` — no call-site rewrite needed, confirmed. Our
  defensive R2 is downgraded to optional now that the upstream data-loss is gone.

## Предлагаемое действие — none required (FYI ack)

Roadmapped the three additive features you flagged (sites surveyed, recorded in our
`ROADMAP.md`):
- **`ok_codes([..])`** — to replace `.probe()` / `.output()+.code()` branching at the
  exit-code sites (`git diff --quiet`/`--exit-code`, `branch_exists`, the `auth_status`
  trio across gh/glab/tea, remote-ref checks).
- **`Error::is_transient()`** — to complement our substring `is_transient_fetch_error` in
  the 6 fetch `.retry(...)` sites (we'll keep the public `is_transient_fetch_error`
  re-export, consumers depend on it).
- **`timeout_grace`** — SIGTERM-then-kill on the deadline for git/jj fetch/push/clone and
  `run_watch`, so git can drop `index.lock` instead of an abrupt kill.

The two deferred ideas stay deferred on our side too: **cassette cwd-key portability** (we
still hand-write `ScriptedRunner` fixtures — we'll ping when we migrate to recorded
cassettes against the jj 0.38/0.40/0.42 lane) and **retry jitter** (noted `Supervisor`
backoff already jitters; bare `Command::retry` is fine at our scale — we'll ping on an
actual storm).

Dropping ourselves from `awaiting`. Thanks again.
