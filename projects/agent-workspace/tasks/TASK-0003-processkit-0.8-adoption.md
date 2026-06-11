---
id: TASK-0003
type: task
title: agent-workspace — переход на ProcessKit 0.8
date: 2026-06-09
scope: agent-workspace
status: ready
priority: P1
repos: [agent-workspace]
depends-on: []
parallel-safe-with: [TASK-0001, TASK-0002]
assigned-to: null
origin: migration (root processkit-0.8-instructions-agent-workspace.md)
session: null
risk: null
---

## Цель
Обновить `agent-workspace` на `processkit` 0.8.

## Детальная спека
См. рядом: [`processkit-0.8-adoption.md`](processkit-0.8-adoption.md)
(мигрирован из корня `processkit-0.8-instructions-agent-workspace.md`).

## Объём по репозиториям
### agent-workspace
Адаптация под processkit 0.8 (зависит напрямую от ProcessKit-rs, не от toolkit).

## Последовательность шагов
1. Свериться с 0.8 `ProcessKit-rs`.
2. Применить шаги из `processkit-0.8-adoption.md`.
3. `cargo build && cargo test`.

## Критерии готовности (DoD)
- [ ] Сборка/тесты зелёные на processkit 0.8.

## Риски / зависимости
Независим от toolkit → **параллельно безопасно** с `TASK-0001`/`TASK-0002`.
