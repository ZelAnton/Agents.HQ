---
id: TASK-0001
type: task
title: vcs-toolkit-rs — переход на ProcessKit 0.8
date: 2026-06-09
scope: vcs-toolkit-rs
status: queued
priority: P1
repos: [vcs-toolkit-rs]
depends-on: []
parallel-safe-with: [TASK-0003]
assigned-to: null
origin: migration (root processkit-0.8-instructions-vcs-toolkit-rs.md)
session: null
risk: null
---

## Цель
Обновить `vcs-toolkit-rs` на `processkit` 0.8.

## Детальная спека
См. исходный документ рядом: [`processkit-0.8-adoption.md`](processkit-0.8-adoption.md)
(мигрирован из корня `processkit-0.8-instructions-vcs-toolkit-rs.md`).

## Объём по репозиториям
### vcs-toolkit-rs
Адаптация под API/поведение processkit 0.8 (детали — в исходном документе).

## Последовательность шагов
1. Свериться с changelog/0.8 `ProcessKit-rs`.
2. Применить шаги из `processkit-0.8-adoption.md`.
3. `cargo build && cargo test`.

## Критерии готовности (DoD)
- [ ] Сборка/тесты зелёные на processkit 0.8.

## Риски / зависимости
Часть rollout'а Rust-линии. Блокирует `TASK-0002` (vcs-flow-rs зависит от vcs-toolkit-rs).
Параллельно безопасно с `TASK-0003` (agent-workspace). См. `../../../knowledge/dependency-graph.md`.
