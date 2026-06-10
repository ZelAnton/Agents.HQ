---
id: INTRA-OV2
type: task
title: intra overlap 2 — функция b2 в shared
repo: .hq-scratch-p5
scope_paths: [src/shared.rs]
build_cmd: cargo build
test_cmd: cargo test
status: ready
priority: P2
---

## Цель
Пересекающаяся подзадача 2 (P5 Case B): добавляет функцию в ту же точку `src/shared.rs`, что и
подзадача 1 → намеренный jj-конфликт при интеграции (обе вставки в одно место).

## DoD
- [ ] Сразу ПОСЛЕ функции `pub fn tag()` в `src/shared.rs` добавь `pub fn b2() -> u32 { 2 }`.
- [ ] Есть `#[test]`, проверяющий `b2() == 2`.
- [ ] `cargo build` и `cargo test` зелёные. Менялся только `src/shared.rs`. Не трогай саму `tag()`.
