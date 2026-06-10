---
id: SCRATCH-LOW
type: task
title: scratch low-risk — добавить чистую функцию double()
repo: .hq-scratch-p4
scope_paths: [src/lib.rs]
build_cmd: cargo build
test_cmd: cargo test
status: ready
priority: P2
---

## Цель
Безопасное in-scope изменение для проверки auto-land (P4 Case-1): добавить маленькую чистую функцию и тест.

## DoD
- [ ] В `src/lib.rs` есть `pub fn double(x: i32) -> i32`, возвращающая `x * 2`.
- [ ] Есть `#[test]`, проверяющий `double(21) == 42`.
- [ ] `cargo build` и `cargo test` зелёные.
- [ ] Менялся только `src/lib.rs` (никаких других файлов, никаких манифестов).
