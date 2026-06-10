---
id: INTRA-A
type: task
title: intra disjoint A — функция в alpha
repo: .hq-scratch-p5
scope_paths: [src/alpha.rs]
build_cmd: cargo build
test_cmd: cargo test
status: ready
priority: P2
---

## Цель
Непересекающаяся подзадача A (P5 Case A): меняет ТОЛЬКО `src/alpha.rs`.

## DoD
- [ ] В `src/alpha.rs` есть `pub fn a_plus(x: i32) -> i32`, возвращающая `x + 10`.
- [ ] Есть `#[test]`, проверяющий `a_plus(5) == 15`.
- [ ] `cargo build` и `cargo test` зелёные. Менялся только `src/alpha.rs`.
