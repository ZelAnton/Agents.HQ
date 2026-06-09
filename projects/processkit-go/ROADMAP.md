# processkit-go — Project Roadmap

> A **native** Go implementation of the processkit model — kernel-backed,
> no-orphan child-process trees. One of five sibling implementations
> (Rust, Python, Go, C#, F# — see *Strategic position*); this one is native Go,
> **not** a binding. Module `github.com/ZelAnton/processkit-go`, package
> `processkit`.

## Strategic position — read first

This project occupies a different square than `processkit-py`. The Python plan
is a thin PyO3 binding: one source of truth (the Rust crate), the binding just
exposes it. Go cannot play that role cheaply — a cgo binding over a tokio crate
is a poor fit (per-call cgo cost, loss of `CGO_ENABLED=0` and trivial
cross-compilation, and tokio's async surface does not cross a C ABI cleanly).

So the governing trade-off is explicit and deliberate:

> **When the goal is "the capability everywhere, from a single source of
> truth", Go falls outside the model — because it requires its own
> implementation, not a binding.**

### The implementation family

The processkit model targets five hosts, which split into two kinds:

- **Independent platform backends** — each carries its *own* copy of the
  dangerous per-platform code (Job Object, cgroup v2, POSIX process groups):
  - **Rust** (`processkit`) — the reference / source of truth.
  - **Go** (`processkit-go`) — this document.
  - **C#** (`processkit-cs`) — a native .NET backend. The author's home turf
    (.NET, prior Job Object interop work), so the most natural of the three to
    own; binding to the Rust core via P/Invoke would hit the same C-ABI / async
    problems as Go's cgo, so native .NET is the right call here too.
- **Cheap layers over a backend, within the same runtime** — no second copy of
  the platform code, because there is no cross-runtime FFI cost:
  - **Python** (`processkit-py`) — PyO3 binding over the Rust core.
  - **F#** (`processkit-fs`) — rides the C# core *inside the CLR*. C# and F#
    share the runtime, so F# calls the C# interop directly and never re-does
    P/Invoke. Its reason to exist is **portfolio** — a strong, idiomatic F#
    project — so its value lives in an idiomatic F# *surface* (discriminated
    unions for results / errors, computation expressions for the builder and
    async), not in duplicating platform code.

So a Go version is one of **three independent platform backends** (rs / go / cs),
not a wrapper. That is the central cost of this roadmap, and the reason to build
it is **reach into the Go ecosystem** (CI / DevOps / infra / build tooling), not
code reuse. If that reach is not worth maintaining a third backend, do not start
this project. The mitigation for the duplication is a *shared behavioural
conformance suite* (see Risk register), not shared code — and it only has to
keep **three** backends honest, since the Python and F# layers inherit their
semantics from the Rust and C# cores respectively.

Each host gets its own roadmap in this folder; this one covers Go.

## Why Go is nonetheless a strong host

Where the Python binding's hardest problems are, Go's are absent:

- **No async-bridge risk.** Goroutines + channels + `context.Context` replace
  the tokio↔asyncio bridge entirely — no async/await coloring, no
  asyncio/trio/anyio fragmentation. Streaming, background stderr drain, and
  `WaitAny` (via `select`) are plain blocking code in goroutines.
- **Cancellation and timeouts are idiomatic, not a feature flag.**
  `context.Context` threads through the whole API and maps onto
  `exec.CommandContext`. What the crate gates behind a `cancellation` feature is
  Go's default.
- **Platform primitives are reachable without FFI pain.** Job Object via
  `golang.org/x/sys/windows`; cgroup v2 via file writes plus — on **Go 1.22+** —
  `SysProcAttr.UseCgroupFD` / `CgroupFD` (`clone3` + `CLONE_INTO_CGROUP`) for
  *atomic* placement of the child into a fresh cgroup at spawn. That closes the
  "no `pre_exec` hook" gap that would otherwise limit Go.
- **The test seam fits the language.** Go interfaces are the natural form for
  `ProcessRunner`; injecting a fake runner is idiomatic — none of the PyO3
  trait-binding awkwardness.
- **Distribution is trivial.** `go get`, simple cross-compilation, no wheel
  matrix, no abi3, no manylinux — provided the build stays pure Go
  (`CGO_ENABLED=0`).

## What does NOT carry over (shared with the Python story)

- **No RAII / `Drop`.** The idiom is `defer group.Close()` + `context`. The
  no-orphan guarantee degrades to "holds as long as you didn't forget the
  `defer`". `runtime.SetFinalizer` is even less reliable than Python's
  `__del__` and must not be used for teardown. (The C# / F# pair faces the same
  thing — `IDisposable` + `using`, with `~Finalizer` no more trustworthy.)
- **Same platform asymmetry.** Windows `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`
  gives a kernel-enforced guarantee that survives a hard kill of the parent;
  Linux cgroup / process-group teardown needs an active kill dispatched from
  the parent (the `defer` / context-cancel path), best-effort only.
- **A Go-specific trap: `Pdeathsig` is unreliable.** The Go runtime multiplexes
  goroutines across OS threads, and `PR_SET_PDEATHSIG` is thread-scoped — the
  signal can fire spuriously when the creating thread exits. Containment must
  rest on the Job Object / cgroup, never on `Pdeathsig`.

## Target API (illustrative, idiomatic Go)

```go
package main

import (
	"context"
	"fmt"
	"time"

	"github.com/ZelAnton/processkit-go"
)

func main() {
	ctx := context.Background()

	// Run-and-capture; a non-zero exit is data, not an error.
	res, err := processkit.Command("git", "rev-parse", "HEAD").Output(ctx)
	if err != nil {
		panic(err)
	}
	fmt.Println(res.Stdout, res.ExitCode)

	// Kill-on-close container for a whole tree.
	group, err := processkit.NewGroup()
	if err != nil {
		panic(err)
	}
	defer group.Close() // reaps the whole tree, grandchildren included

	server, err := group.Start(ctx, processkit.Command("my-server"))
	if err != nil {
		panic(err)
	}
	// Cancelling ctx (or hitting the timeout) tears the tree down.
	if err := server.WaitForPort(ctx, "127.0.0.1:8080", 10*time.Second); err != nil {
		panic(err)
	}
	// ... use the server ...
}
```

API-style fork to settle early: a Rust-like fluent builder vs the Go-idiomatic
*functional options* / config struct. Leaning toward functional options for the
verb-level knobs (timeout, env, stdin) and a small `Cmd` value for the program +
args. See Open decisions.

## Architecture decisions

- **Pure Go, `CGO_ENABLED=0`.** All platform access through `golang.org/x/sys`
  syscalls, never cgo — this is what keeps cross-compilation and distribution
  trivial, and is the whole reason Go is viable as a native target.
- **`context.Context` first.** Every blocking verb takes a `ctx`; cancellation
  and deadlines flow through it onto the process tree.
- **Containment backends** mirror the crate: Windows Job Object, Linux cgroup v2
  (with a process-group fallback), POSIX process group on macOS / BSD; the
  active mechanism is observable, never a silent downgrade.
- **Go version floor: 1.22** to get `CgroupFD` atomic cgroup placement (with a
  file-write fallback path for older kernels / non-delegated cgroups).

## Naming & publishing

Go has no central package registry — the import path *is* the repository URL, so
"availability" reduces to the repo name under the handle, which is owned.

- **Module path:** `github.com/ZelAnton/processkit-go`.
- **Package name:** `processkit` (the directory ends in `-go`, which is not a
  legal Go identifier, so the package is declared `processkit` — conventional,
  cf. `gopkg.in/yaml.v3` → package `yaml`; no import alias needed downstream).
- **Repository:** `processkit-go`, beside `ProcessKit-rs`, `processkit-py`,
  `processkit-cs`, and `processkit-fs` — the `-rs` / `-py` / `-go` / `-cs` /
  `-fs` suffix family reads as "same model, five hosts". (NuGet package-id
  availability for the C# / F# packages is a check for those roadmaps, not this
  one.)
- Indexed automatically by pkg.go.dev from the module path.

---

## Phases

### Phase 0 — De-risk spikes  *(effort: S, blocking)*

The risky unknowns differ from the Python plan — they are about *spawning*, not
about an async bridge.

- **cgroup atomic placement.** Prove `CgroupFD` (`clone3` + `CLONE_INTO_CGROUP`)
  lands a child in a fresh cgroup at spawn under Go 1.22+, and that the whole
  subtree dies on teardown. Verify the file-write fallback for older kernels.
- **Windows race-free job assignment.** `os/exec` does not expose the child's
  primary thread handle, so the crate's `CREATE_SUSPENDED → assign → resume`
  needs reconstruction in Go (CreationFlags + a Toolhelp thread snapshot to find
  and resume the primary thread). Prove a grandchild spawned in the assignment
  window is still contained.
- **Confirm `Pdeathsig` is NOT load-bearing.** Demonstrate the spurious-fire
  hazard and that containment holds without it.

**Exit criteria:** child → grandchild spawned, `ctx` cancelled, grandchild
proven dead on Windows and Linux; no reliance on `Pdeathsig`.

### Phase 1 — Core: command, capture, containment  *(effort: M)*

- `Command` value; `Run` / `Output` / `ExitCode` / `Probe` verbs, all taking
  `ctx`.
- `Group` with `Close()` containment on all three mechanisms — the
  `defer`-based explicit-cleanup design made real.
- Context cancellation + deadlines wired through from day one (no separate async
  phase — this is the Go payoff).
- **Error model:** typed errors with `errors.Is` / `errors.As` (sentinel
  `ErrTimeout`, `ErrCancelled`, `ErrUnsupported`, `ErrResourceLimit`, plus a
  rich `*ExitError`). Decide sentinel-vs-struct split in this phase.

**Exit criteria:** `go get` the module on Win + Linux + macOS, capture a
command into a typed result, orphan-leak test passes on the `defer Close()`
path.

### Phase 2 — Streaming & interactive I/O  *(effort: M)*

- `RunningProcess`: stdout line streaming over a channel (`for line := range
  proc.StdoutLines()`), background stderr drain, interactive stdin.
- `WaitAny` over several running processes via `select` — the natural Go form.
- Stream/cancel interplay: cancelling `ctx` mid-stream kills the tree and closes
  the channel; the follow-up reports `ErrCancelled`.

**Exit criteria:** stream a long-running child line by line; cancel `ctx`
mid-stream; tree reaped, result reports `ErrCancelled`.

### Phase 3 — Higher-level features  *(effort: L, demand-ordered)*

- **Supervisor** — restart policies, backoff, stop conditions. High value for
  the service / infra niche.
- **Readiness probes** — `WaitForLine` / `WaitForPort` / `WaitFor`.
- **Resource limits** — memory / process-count / CPU caps on the tree
  (Job Object + cgroup); the real differentiator for sandboxing untrusted trees.
- **Pipelines** — shell-free `a | b | c` with pipefail attribution. Medium.
- **Signals / suspend / resume / members / stats** — expose incrementally.

### Phase 4 — Test seam, docs  *(effort: S–M)*

- **`ProcessRunner` interface** + a scripted fake — idiomatic Go dependency
  injection, plus optional record/replay fixtures.
- **godoc** with runnable `Example` functions; a cookbook mirroring the crate's
  "I want to … → snippet".

### Phase 5 — Hardening & v1.0  *(effort: M)*

- Platform-caveat matrix documented end to end (mirror the crate's honesty).
- Leak / stress tests: parent `SIGKILL`, panic paths, `os.Interrupt`, on every
  mechanism.
- `go test -race` clean across the streaming and supervisor paths.
- Performance sanity (syscall-bound; just confirm no silly overhead).
- API-stability commitment under Go's compatibility expectations + semver.

---

## Risk register

- **A third independent platform backend (rs / cs / go).** The strategic cost
  (see Strategic position). Mitigation: a **shared cross-language behavioural
  conformance suite** — a spec plus black-box tests. It only has to keep the
  three *backends* aligned; the Python and F# layers inherit their semantics
  from the Rust and C# cores, so the platform fine print lives in the spec, not
  in three drifting heads.
- **Windows race-free job assignment** without an exposed thread handle.
  Mitigation: Phase 0 spike (Toolhelp snapshot + resume); accept the documented
  residual window if it proves unavoidable, as the crate does.
- **cgroup delegation requirements** (root / container / `Delegate=yes`), kernel
  version, Go 1.22 floor for `CgroupFD`. Mitigation: file-write fallback;
  `ErrResourceLimit` instead of a silently-unbounded group.
- **No RAII → discipline-dependent teardown.** Mitigation: `defer Close()` +
  `context`; lean on Windows `KILL_ON_JOB_CLOSE`; document Linux best-effort.
- **`Pdeathsig` spurious fire.** Mitigation: never rely on it; Phase 0 proves
  containment without it.

*Risk explicitly eliminated vs the Python plan: there is no async-bridge risk.*

## Non-goals (deliberate scope cuts)

- **Not a binding** to the Rust crate (no cgo) — a native reimplementation by
  design; that is the whole point of this square.
- No cgo, ever — `CGO_ENABLED=0` is a hard constraint.
- Not a general `os/exec` convenience wrapper — cede that to the stdlib.
- No reliance on `Pdeathsig`.
- No cgroup v1, no Windows pre-10.

## Open decisions

1. **API style** — Rust-like fluent builder vs Go functional options
   (leaning: functional options + a small `Cmd` value).
2. **Error model** — sentinel errors (`errors.Is`) vs typed structs
   (`errors.As`); likely both, with a clear split.
3. **Go version floor** — commit to 1.22 (for `CgroupFD`) or support older with
   the file-write fallback as the only Linux atomic-placement path.
4. **Parity vs idiom** — mirror the crate's surface exactly, or diverge where Go
   idiom clearly differs (channels for streams, `context` for cancellation).
5. **Conformance suite ownership** — where the shared behavioural spec lives
   (covering the rs / go / cs backends, with py / fs validated for surface
   fidelity to their cores) and how each implementation runs it in CI.
6. **Whether to build this at all** — gated on whether Go-ecosystem reach
   justifies a third platform backend (see Strategic position).
