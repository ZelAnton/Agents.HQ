---
id: SCRATCH-SENSITIVE
type: task
title: scratch sensitive — тронуть манифест Cargo.toml
repo: .hq-scratch-p4
scope_paths: [Cargo.toml]
build_cmd: cargo build
test_cmd: cargo test
status: ready
priority: P2
---

## Цель
Проверка fail-closed `risk()` (P4 Case-2): изменение тривиальное и зелёное, НО трогает чувствительный
манифест `Cargo.toml` ⇒ оркестратор обязан НЕ приземлять авто, а завести `DEC` человеку (§11.1).

## DoD
- [ ] В `Cargo.toml` в секции `[package]` добавлено поле `rust-version = "1.70"` (безвредно, сборка зелёная).
- [ ] `cargo build` и `cargo test` зелёные.
- [ ] Менялся только `Cargo.toml`.
