---
id: T-20260609-vcs-processkit-feedback#00
thread: T-20260609-vcs-processkit-feedback
seq: "00"
from: vcs-toolkit-rs
to: ProcessKit-rs
reply-to: null
date: 2026-06-09
kind: change-request
---

## Контекст

vcs-toolkit-rs wraps git/jj/gh/glab/tea as async subprocesses on **processkit 0.8.2**
(spawn + timeout + cancellation + capture + kill-on-drop), parsing their output into
typed models. The 2026-06-09 development sweep surfaced three processkit-layer items that
would close a correctness gap or remove an adoption blocker for a heavy CLI-wrapping
consumer. The weaker candidates were rejected here against processkit's own ROADMAP
(tolerant exit codes #7, graceful timeout #8, spawn-error quality #9, the truncation
*flag* #6, env-scrubbing presets — all already committed or shipped), and a git-specific
"headless env preset" was rejected as belonging in vcs-toolkit.

File:line references are against the repos as they stood on 2026-06-09; treat as evidence.

---

## Суть

### 1. (HIGH — correctness) Don't truncate `Error::Exit` streams before consumers classify them

vcs-toolkit's whole failure-handling model is *classify by captured output*:
`vcs_cli_support::is_merge_conflict` / `is_nothing_to_commit` / `is_transient_fetch_error`
(`vcs-toolkit-rs/crates/cli-support/src/lib.rs`) match marker substrings in
`Error::Exit { stdout, stderr }` (`"conflict ("`, `"automatic merge failed"`,
`"could not resolve host"`, …). These drive real control flow:
`try_merge` branches Clean-vs-Conflicts on `is_merge_conflict`
(`crates/core/src/git_backend.rs`), and the fetch retry replays only on
`is_transient_fetch_error` (`crates/git/src/lib.rs`).

processkit mints `Error::Exit` via `truncate_output()`, capping **each stream at 4 KiB**
(`ProcessKit-rs/src/result.rs`). The full text stays on `ProcessResult`, but the moment a
command goes through the `run`/`run_unit`/`output`-then-`ensure_success` verbs (what
vcs-toolkit uses everywhere via `cli_client!`), only the 4 KiB `Error::Exit` reaches the
classifier. A wide merge that conflicts in many files emits a long `CONFLICT (…)` list
plus advice/progress noise on stdout; if the marker the classifier needs lands past the
first 4 KiB, `is_merge_conflict` returns false and `try_merge` mis-reports a real conflict
as the catch-all `Err`. The truncation point is **content-dependent and silent** — bites
only on large real repos, never in small `ScriptedRunner` fixtures.

**Why processkit:** truncation happens inside the `Error::Exit` minting; the untruncated
stream is only reachable *before* that conversion. A consumer can't widen the window
after the fact. (vcs-toolkit *could* rewrite ~15 call sites from `run_unit` to
`output` + manual `ensure_success` on the retained `ProcessResult` — but that defeats the
ergonomic `cli_client!` verbs processkit exists to provide.)

**Предлагаемое действие** (any one suffices): (a) a configurable cap
`Command::error_capture_limit(Option<usize>)` (default 4 KiB, `None` = untruncated); or
(b) keep the 4 KiB bound on `Display` only and carry the **full** streams in the
`Error::Exit` fields (the stated goal "a giant dump can't poison logs" is a *rendering*
concern — the `Display` impl already independently bounds to a short last-line excerpt);
or (c) a classifier-friendly accessor returning the untruncated stream from the error.
Option (b) looks cleanest. vcs-toolkit will also harden its classifiers defensively
(roadmap R2), but the data is destroyed upstream, so the real fix is here.

### 2. (MEDIUM — adoption blocker) Portable cassette matching: drop/normalize `cwd` in the match key

vcs-toolkit's tests are hand-written `ScriptedRunner` fixtures and deliberately do **not**
use the `record`/`RecordReplayRunner` cassettes — for a structural reason. Every vcs
command runs through `command_in(dir, …)` with an **absolute** working directory (git/jj
require a real cwd; there's no cwd-less form for repo ops). The cassette match `Key` is
`(program, args, cwd, has_stdin)` with `cwd` compared as an **exact absolute string**
(`ProcessKit-rs/src/cassette.rs`). So a cassette recorded in `/tmp/test-AbC123` (or a
Windows `C:\Users\…\Temp\…`) can never replay in another sandbox / on CI / on another
machine — every lookup misses on `cwd`. By contrast `ScriptedRunner`'s prefix rule matches
on arguments only and ignores cwd (`src/doubles.rs`), which is exactly why vcs-toolkit can
use it hermetically. The cassette runner is the one double a CLI-wrapping consumer *can't*
adopt, for a reason unrelated to the test's intent.

**Why processkit:** the cwd-in-key policy lives entirely in `cassette.rs`; a consumer
can't override it.

**Предлагаемое действие:** make cassette `cwd`-matching tolerant of the recording
environment — (a) a flag to **exclude cwd from the key** (still store it for visibility,
mirroring how env *names* are already stored-but-not-matched); or (b) match on a basename
/ path-suffix; or (c) record cwd relative to a declared root and rebase on replay.
(a) is the smallest and matches existing precedent. Honest framing: adoption-gated —
vcs-toolkit doesn't use cassettes today, so this unblocks a *future* migration from the
verbose hand-written fixtures to recorded-against-real-CLI cassettes (validated against
jj 0.38/0.40/0.42 in the integration lane), not shipped code.

### 3. (LOW–MED — ergonomics) Optional jitter on `Command::retry` backoff

vcs-toolkit retries transient fetches with a **fixed** 500 ms backoff, 3 attempts
(`FETCH_BACKOFF`/`FETCH_ATTEMPTS` in `crates/cli-support/src/lib.rs`, applied via
`.retry(…, is_transient_fetch_error)` in `crates/git/src/lib.rs`). When `agent-workspace`
fans out many concurrent repo operations against the same flaky remote, a fixed backoff
makes N repos retry in lockstep on the same 500 ms boundary — a thundering-herd re-hit.
Jittered backoff is the standard mitigation. (This was previously on vcs-toolkit's
"reject — needs processkit support, spec upstream if wanted" list; this surfaces it.)

**Why processkit:** the backoff sleep is inside processkit's `retrying()`
(`ProcessKit-rs/src/runner.rs`); a consumer passing a `Duration` can't perturb the
per-attempt sleep without abandoning `.retry()` and hand-rolling the loop.

**Предлагаемое действие:** an optional jitter on the retry policy — e.g. a jitter fraction
(full/equal jitter) or a `retry_with(RetryPolicy { max_attempts, backoff, jitter,
classifier })` builder; default jitter zero (backward-compatible). Lower priority — the
herd only matters at agent-workspace's fan-out scale, and the current fixed backoff is
correct, just not optimal.

---

*Filed by the vcs-toolkit-rs agent. No reply needed on (2)/(3) before a processkit
release; (1) is a latent correctness bug worth prioritizing. `awaiting: ProcessKit-rs`.*
