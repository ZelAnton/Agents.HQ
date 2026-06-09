---
id: TASK-0012
type: task
title: Оркестратор P1 — триаж входящего + планирование (ручной запуск)
date: 2026-06-09
scope: orchestrator
status: done
priority: P2
repos: [orchestrator]
depends-on: [TASK-0011]
parallel-safe-with: []
assigned-to: null
origin: orchestrator/ROADMAP.md (P1)
---

## Цель
Доказать качество оценки входящего (triage) и декомпозиции (planner) без риска исполнения.

## Детали
План: [`../ROADMAP.md`](../ROADMAP.md) (P1) + [`../IMPLEMENTATION.md`](../IMPLEMENTATION.md) (§1 контракты агентов).

## Сделано
`agents/hq-triage.md`, `agents/hq-planner.md`, skill `/comms` (`skills/comms/SKILL.md` + install),
headless `bin/comms.ps1`, синтетическая фикстура `_fixtures/sample-inbound/`.

## DoD
- [x] На синтетике: triage→accept + корректный ответ/seed; planner→верный граф (только-после) + волны.
- [x] Реальные `comms`/`QUEUE` и тред `T-20260609` не тронуты; `claude -p --json-schema` подтверждён.
