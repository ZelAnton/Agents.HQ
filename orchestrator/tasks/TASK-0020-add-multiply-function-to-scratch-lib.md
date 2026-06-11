---
id: TASK-0020
type: task
title: Add multiply function to scratch lib
date: 2026-06-10
scope: .hq-scratch-e2e-m3b
status: done
priority: P2
repos: [.hq-scratch-e2e-m3b]
scope_paths: [src/]
depends-on: []
parallel-safe-with: []
assigned-to: null
origin: human
created-by: human
risk: low
autonomy: auto-low
fix-attempt: 0
session: null
blocked-reason: null
review: pass
---

## Цель

Add a `pub fn multiply(a: u64, b: u64) -> u64` function to `src/lib.rs` and a test
that proves `multiply(3, 4) == 12`. Only modify `src/lib.rs`.

## Объём по репозиториям

Только `src/lib.rs` (scope_paths: `[src/]`).

## Критерии готовности (DoD)

- [ ] `src/lib.rs` contains `pub fn multiply(a: u64, b: u64) -> u64 { a * b }`
- [ ] `src/lib.rs` contains a `#[test] fn test_multiply()` that asserts `multiply(3, 4) == 12`
- [ ] `cargo build` exits 0
- [ ] `cargo test` exits 0 with all tests passing (including the new one)

## Инструкции для исполнителя

1. Open `src/lib.rs`.
2. Add the function after the existing `pub fn add`:
   ```rust
   pub fn multiply(a: u64, b: u64) -> u64 { a * b }
   ```
3. Add a test in the `#[cfg(test)] mod tests` block:
   ```rust
   #[test]
   fn test_multiply() { assert_eq!(multiply(3, 4), 12); }
   ```
4. Run `cargo build` and `cargo test` — both must exit 0.
5. Run `jj describe -m "feat: add multiply function"`.
6. Return JSON status: `done`.

