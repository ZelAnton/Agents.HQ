# ProcessKit-rs — Streaming-Hardening Requirements (from vcs-toolkit-rs)

A requirements note from the `vcs-toolkit-rs` project (the `vcs-git` / `vcs-jj` /
`vcs-github` / `vcs-core` crates, which build on `processkit`'s `CliClient`).
Same contract as the earlier `Error::Exit.stdout` requirement: vcs-toolkit does
**not** fork or vendor processkit — needs are raised here as behavioural
requirements, processkit decides the implementation.

**Status.** Requirements, not commitments. Validated against processkit
**0.6.1** source (file:line references below refer to it).

---

## Motivation

vcs-toolkit drives long-running commands whose only signal today is the final
exit: `git clone` / `git fetch` / `git push` (network progress on stderr),
`jj git clone`, and `gh run watch` (a watch that can legitimately run for an
hour, printing heartbeat lines). Consumers building interactive UIs
(vcs-flow-rs) want line-level progress while the command runs.

**What 0.6 already provides — this is NOT a request to add streaming.**
`Command::on_stdout_line(F)` / `on_stderr_line(F)` with
`F: Fn(&str) + Send + Sync + 'static` (`command.rs:181-198`), plus the
`RunningProcess::stdout_lines()` stream (`running.rs:221`). Since
`CliClient::command()/command_in()` return that same `Command`
(`client.rs:98-108`), a vcs-toolkit wrapper can attach handlers today. The
requirements below are about making that surface **safe to bless** in
vcs-toolkit's public API.

---

## R1 — Callback panic isolation (primary)

**Today.** A panicking line handler unwinds inside the pump task; processkit
only guarantees the sink is closed (`pump.rs:148-149, 255-272`), and the
`on_*_line` docs say "keep it cheap and **panic-free**".

**Requirement.** A panic in a user-supplied line handler must not poison the
run: the child keeps being drained (or is killed cleanly), the final
`ProcessResult` (or a structured error attributing the panic to the handler)
is still produced, and the panic does not cross into unrelated tasks. A
`catch_unwind` around the handler invocation with a documented policy
(disable the handler for the rest of the run, record the fact) would satisfy
this. Rationale: vcs-toolkit hands the callback seam to *its* consumers — it
cannot audit their closures, so "panic-free or UB-adjacent behaviour" is not a
contract we can re-export.

**Acceptance.** A test in processkit: a handler that panics on the 2nd line of
a 10-line child → the run completes, the captured result contains all 10 lines,
some structured signal reports the handler failure.

## R2 — Ordering guarantees (document, not necessarily change)

**Requirement.** Document the guaranteed ordering between (a) handler
invocations for stdout vs stderr lines (presumably none across streams,
FIFO within a stream), and (b) the last handler invocation vs the resolution
of the run's future / availability of the final `ProcessResult` (handlers
must have quiesced before the result is returned — or the opposite, stated
explicitly). vcs-toolkit needs to know whether a progress bar can be finalized
the moment the awaited call returns.

**Acceptance.** Doc section on `on_stdout_line`/`on_stderr_line` stating both
guarantees, with a test pinning "all handler calls happen-before the run
future resolves" (or the documented alternative).

## R3 — Test doubles replay canned output through handlers

**Today.** `ScriptedRunner::output()` fabricates a finished `ProcessResult`
from the `Reply` (`doubles.rs`) — it never touches the pump, so line handlers
attached to the `Command` are **silently ignored** in hermetic tests. A
vcs-toolkit method that streams progress cannot be tested hermetically: the
canned stdout never reaches the callback.

**Requirement.** When a `Command` carries line handlers, `ScriptedRunner`
(and `RecordingRunner` pass-through) should replay the `Reply`'s stdout/stderr
line-by-line through those handlers before returning the result — mirroring
the live contract closely enough that a consumer's streaming logic is testable
without a real binary.

**Acceptance.** `ScriptedRunner::new().on(["fetch"], Reply::ok("a\nb\n"))`
against a command with `on_stdout_line` → the handler observes `["a", "b"]`
and the returned result still carries the full stdout.

## R4 (secondary, optional) — cross-cutting command hook

A convenience, not a capability gap: argv-level observation already works by
wrapping the runner (`RecordingRunner::new(JobRunner::new())`), and per-call
output observation works via R1-R3. If processkit ever wants a first-class
`on_command(|cmd| …)` hook on `CliClient` (one registration instead of a
wrapper runner), vcs-toolkit would adopt it — but it ranks strictly below
R1-R3. **No new runner type is requested.**

---

## Consumer sketch (what vcs-toolkit will build on top)

```rust
// vcs-git, once R1+R2 land — a fetch that reports progress lines:
pub async fn fetch_with_progress<F>(&self, dir: &Path, on_line: F) -> Result<()>
where
    F: Fn(&str) + Send + Sync + 'static,
{
    let cmd = self
        .core
        .command_in(dir, ["fetch", "--progress"])
        .env("GIT_TERMINAL_PROMPT", "0")
        .on_stderr_line(on_line); // git writes progress to stderr
    self.core.unit(cmd).await
}
```

Hermetic testing of that method is exactly the R3 gap.

## Compatibility

- No breaking changes requested: R1/R2 harden existing semantics, R3 extends
  the doubles, R4 is additive.
- vcs-toolkit will gate its streaming wrappers on the processkit release that
  ships R1 (and R3 for their tests), pinned via `[workspace.dependencies]`.

---

## Response (processkit, 2026-06-07)

**R1 — ACCEPTED, implemented.** A panicking line handler is caught
(`catch_unwind` around the invocation), **disabled for the rest of the run**,
and reported as a `tracing` warn (`tracing` feature); the pump keeps draining,
so the child never blocks and the final result carries **every** line. The
spec's acceptance test is in processkit's suite verbatim (panic on line 2 of
10 → all 10 captured, handler called exactly twice). The structured signal is
the tracing event + the documented policy on `on_stdout_line` — no new error
variant (capture succeeding is the contract; the panic is diagnostics).

**R2 — ACCEPTED, documented + pinned.** `on_stdout_line` now states: FIFO
within a stream; no ordering across stdout/stderr (independent pumps); on the
consuming verbs all handler invocations **happen-before the awaited future
resolves** (pin test in the suite) — finalize the progress bar the moment the
call returns. One documented exception: a leaked pipe held open past the
child's death is cut off after the bounded teardown grace. On a streamed run,
stdout handlers quiesce when the `stdout_lines` stream ends.

**R3 — ACCEPTED, implemented (and exceeded).** `ScriptedRunner::output`
replays canned stdout/stderr through the command's handlers before returning
(the spec's acceptance test is in the suite). Beyond the ask: `start()` joined
the `ProcessRunner` seam — `ScriptedRunner::start` returns a **scripted
`RunningProcess`** whose canned lines flow through the same pump machinery as
a real child, so `stdout_lines`/`wait_for_line`/`finish_streamed` are now
hermetically testable too (`Reply::lines([...])`, `.with_line_delay(d)` for
paced delivery under a paused clock). Scripted handles have no pid, don't
compose into a real `Pipeline`, and don't model interactive stdin.

**R4 — DECLINED**, same verdict as the cancellation spec's R3 (`default_map`):
a stored `Fn(Command) -> Command`/`on_command` hook loses to typed, narrow
defaults on introspection and documentation, and argv observation already
works via `RecordingRunner`. Revisit only if a third typed "apply to every
command" candidate accumulates — then as ONE design.

**Ships in:** the next processkit release (**0.8.0** — note it carries
breaking changes: `SupervisionOutcome` is `#[non_exhaustive]`, and
`CliClient`'s verbs were renamed `text/capture/unit/code` →
`run/output/run_unit/exit_code`; the migration instruction in
`d:\GitHub\Personal\processkit-0.8-instructions-vcs-toolkit-rs.md` covers it).
