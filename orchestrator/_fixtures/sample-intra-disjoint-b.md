---
id: INTRA-B
type: task
title: intra disjoint B — функция в beta
repo: .hq-scratch-p5
scope_paths: [src/beta.rs]
build_cmd: cargo build
test_cmd: cargo test
status: ready
priority: P2
---

## Цель
Непересекающаяся подзадача B (P5 Case A): меняет ТОЛЬКО `src/beta.rs`. Параллельна A (разные файлы).

## DoD
- [ ] В `src/beta.rs` есть `pub fn b_times(x: i32) -> i32`, возвращающая `x * 3`.
- [ ] Есть `#[test]`, проверяющий `b_times(4) == 12`.
- [ ] `cargo build` и `cargo test` зелёные. Менялся только `src/beta.rs`.
