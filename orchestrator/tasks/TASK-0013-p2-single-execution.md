---
id: TASK-0013
type: task
title: Оркестратор P2 — исполнение одной задачи в изоляции
date: 2026-06-09
scope: orchestrator
status: ready
priority: P2
repos: [orchestrator]
depends-on: [TASK-0012]
parallel-safe-with: []
assigned-to: null
origin: orchestrator/ROADMAP.md (P2)
---

## Цель
Безопасно исполнить ОДНУ подзадачу изолированно (без параллелизма).

## Детали
План: [`../ROADMAP.md`](../ROADMAP.md) (P2) + [`../IMPLEMENTATION.md`](../IMPLEMENTATION.md) (§1 Executor, §3 claim, §6 сбои).

## Объём / что делаем
- Агент `hq-exec` (skill/headless) + его спец `agents/hq-exec.md`.
- Дирижёр берёт одну `ready`-задачу, заводит jj-workspace через `agent-workspace` (`ws`), запускает
  исполнителя, собирает структурный результат (`executor-result.schema.json`).
- Сборка/тесты по командам из `projects/<repo>/card.md`; diff на ревью человеку; откат `jj abandon`.

## DoD
- [ ] Реальная подзадача выполнена в отдельной workspace, тесты зелёные, человек заland-ил; основной репо не затронут.

## Зависимости
Только-после P1 (нужны контракты/спецы агентов).
