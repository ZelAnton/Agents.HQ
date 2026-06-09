---
id: TASK-0002
type: task
title: vcs-flow-rs — переход на ProcessKit 0.8
date: 2026-06-09
scope: vcs-flow-rs
status: queued
priority: P1
repos: [vcs-flow-rs]
depends-on: [TASK-0001]
parallel-safe-with: [TASK-0003]
assigned-to: null
origin: migration (root processkit-0.8-instructions-vcs-flow-rs.md)
---

## Цель
Обновить `vcs-flow-rs` на `processkit` 0.8.

## Детальная спека
См. рядом: [`processkit-0.8-adoption.md`](processkit-0.8-adoption.md)
(мигрирован из корня `processkit-0.8-instructions-vcs-flow-rs.md`).

## Объём по репозиториям
### vcs-flow-rs
Адаптация под processkit 0.8 после обновления `vcs-toolkit-rs`.

## Последовательность шагов
1. Дождаться `TASK-0001` (vcs-toolkit-rs на 0.8).
2. Применить шаги из `processkit-0.8-adoption.md`.
3. `cargo build && cargo test`.

## Критерии готовности (DoD)
- [ ] Сборка/тесты зелёные на processkit 0.8 поверх обновлённого toolkit.

## Риски / зависимости
**Only-after `TASK-0001`** — vcs-flow-rs зависит от vcs-toolkit-rs (см. `../../../knowledge/dependency-graph.md`).
