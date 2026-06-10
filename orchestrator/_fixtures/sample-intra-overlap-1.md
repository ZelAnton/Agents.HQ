---
id: INTRA-OV1
type: task
title: intra overlap 1 — функция b1 в shared
repo: .hq-scratch-p5
scope_paths: [src/shared.rs]
build_cmd: cargo build
test_cmd: cargo test
status: ready
priority: P2
---

## Цель
Пересекающаяся подзадача 1 (P5 Case B): добавляет функцию в `src/shared.rs` рядом с другой такой же
подзадачей → при интеграции возникает jj-конфликт, который чинит `hq-merge`.

## DoD
- [ ] Сразу ПОСЛЕ функции `pub fn tag()` в `src/shared.rs` добавь `pub fn b1() -> u32 { 1 }`.
- [ ] Есть `#[test]`, проверяющий `b1() == 1`.
- [ ] `cargo build` и `cargo test` зелёные. Менялся только `src/shared.rs`. Не трогай саму `tag()`.
