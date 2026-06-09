---
id: EXEC-FIXTURE-02
type: task
title: (ФИКСТУРА) agent-workspace — smoke-тест оркестратора
date: 2026-06-10
scope: agent-workspace
status: ready
priority: P2
repos: [agent-workspace]
scope_paths: [tests/_orchestrator_smoke.rs]
depends-on: []
parallel-safe-with: []
assigned-to: null
origin: P3 validation fixture (безопасная микро-задача в ДРУГОМ репо, НЕ лендить)
build_cmd: cargo build
test_cmd: cargo test --test _orchestrator_smoke
fixture: true
---

## Цель
Безопасная микро-задача в **agent-workspace** (другой репозиторий) для валидации P3 — параллельное
исполнение в РАЗНЫХ репо. Полностью обратима, не трогает продуктовый код, не для приземления.

## Что сделать
Создать **новый** файл `tests/_orchestrator_smoke.rs` с одним тривиальным тестом:

```rust
// Smoke-тест оркестратора (P3, кросс-репо). Безопасно. НЕ лендить.
#[test]
fn orchestrator_smoke_p3() {
    assert_eq!(3 + 4, 7);
}
```

Затем: `cargo build` и `cargo test --test _orchestrator_smoke`.

## Область (scope_paths)
Только `tests/_orchestrator_smoke.rs` (новый файл).

## Критерии готовности (DoD)
- [ ] Файл создан с указанным тестом.
- [ ] `cargo build` ok; `cargo test --test _orchestrator_smoke` pass.
- [ ] `out_of_scope_touched` пуст.
