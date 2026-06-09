---
id: TASK-0017
type: task
title: Оркестратор P6 — hardening, масштаб, наблюдаемость
date: 2026-06-09
scope: orchestrator
status: queued
priority: P2
repos: [orchestrator]
depends-on: [TASK-0016]
parallel-safe-with: []
assigned-to: null
origin: orchestrator/ROADMAP.md (P6)
---

## Цель
Надёжная безнадзорная работа.

## Детали
План: [`../ROADMAP.md`](../ROADMAP.md) (P6) + [`../IMPLEMENTATION.md`](../IMPLEMENTATION.md) (§2, §6, §8).

## Объём / что делаем
- `hq-conductor` как Rust-бинарь (догфуд **processkit** + **vcs-toolkit-rs** + **agent-workspace**):
  устойчивый планировщик, лизы/claim, восстановление после краша (состояние из `.hq`).
- **tessmux**-дашборд, метрики (пропускная способность, % конфликтов/эскалаций/зелёных тестов, % автономии),
  бюджеты, record/replay-тесты тиков (processkit), полные режимы автономии per-repo.

## DoD
- [ ] Несколько тиков подряд без присмотра с восстановлением после сбоя; дашборд и метрики; воспроизводимые прогоны в тестах.

## Зависимости
Только-после P5.
