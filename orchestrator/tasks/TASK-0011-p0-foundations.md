---
id: TASK-0011
type: task
title: Оркестратор P0 — фундамент (схемы, контракты, dry-run)
date: 2026-06-09
scope: orchestrator
status: done
priority: P2
repos: [orchestrator]
depends-on: []
parallel-safe-with: []
assigned-to: null
origin: orchestrator/ROADMAP.md (P0)
---

## Цель
Зафиксировать контракты (схемы, состояние, dry-run), чтобы дальше всё стыковалось без переделок.

## Детали
План фазы: [`../ROADMAP.md`](../ROADMAP.md) (P0) + [`../IMPLEMENTATION.md`](../IMPLEMENTATION.md) (§1 контракты, §3 состояние).

## Сделано
`schemas/*` (triage/planner/tick-log/executor-result), `STATE.md`, `STATUS(.template).md`,
поле `autonomy` в шаблоне карточки, `_runs/`.

## DoD
- [x] Схемы валидны; STATE/STATUS заданы; конвенция `autonomy` документирована; dry-run определён.
