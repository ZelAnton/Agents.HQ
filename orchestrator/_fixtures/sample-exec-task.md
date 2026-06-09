---
id: EXEC-FIXTURE-01
type: task
title: (ФИКСТУРА) ProcessKit-rs — smoke-тест оркестратора
date: 2026-06-09
scope: ProcessKit-rs
status: ready
priority: P2
repos: [ProcessKit-rs]
scope_paths: [tests/_orchestrator_smoke.rs]
depends-on: []
parallel-safe-with: []
assigned-to: null
origin: P2 validation fixture (безопасная микро-задача, НЕ лендить)
build_cmd: cargo build
test_cmd: cargo test --test _orchestrator_smoke
fixture: true
---

## Цель
Безопасная микро-задача для валидации P2 (исполнение в изолированной jj-workspace). Полностью обратима,
не трогает продуктовый код, не предназначена для приземления.

## Что сделать
Создать **новый** файл `tests/_orchestrator_smoke.rs` с одним тривиальным интеграционным тестом:

```rust
// Smoke-тест оркестратора (P2). Безопасно, не трогает логику крейта. НЕ лендить.
#[test]
fn orchestrator_smoke() {
    assert_eq!(2 + 2, 4);
}
```

Затем собрать и прогнать именно этот тест: `cargo build` и `cargo test --test _orchestrator_smoke`.

## Область (scope_paths)
Только `tests/_orchestrator_smoke.rs` (новый файл). Ничего больше не трогать.

## Критерии готовности (DoD)
- [ ] Файл `tests/_orchestrator_smoke.rs` создан с указанным тестом.
- [ ] `cargo build` — `ok`; `cargo test --test _orchestrator_smoke` — `pass`.
- [ ] `out_of_scope_touched` пуст.
