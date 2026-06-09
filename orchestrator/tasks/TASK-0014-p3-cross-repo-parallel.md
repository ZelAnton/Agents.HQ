---
id: TASK-0014
type: task
title: Оркестратор P3 — параллель между репозиториями (без конфликтов)
date: 2026-06-09
scope: orchestrator
status: done
priority: P2
repos: [orchestrator]
depends-on: [TASK-0013]
parallel-safe-with: []
assigned-to: null
origin: orchestrator/ROADMAP.md (P3)
---

## Цель
Несколько готовых задач в РАЗНЫХ репозиториях — параллельно за один тик (конфликтов нет в принципе).

## Детали
План: [`../ROADMAP.md`](../ROADMAP.md) (P3) + [`../IMPLEMENTATION.md`](../IMPLEMENTATION.md) (§5 планирование, §2 дирижёр).

## Объём / что делаем
- `Scheduler` в Дирижёре: ready-set из графа, лимит параллелизма, claim, ws на задачу.
- Запуск/надзор исполнителей через **processkit** (конкурентность, таймауты, отмена).
- **tessmux** — живой обзор сессий; гейт тестов перед предложением land; land — человек.

## DoD
- [x] 2 кросс-репо задачи (ProcessKit-rs + agent-workspace) выполнены **параллельно** за тик через `hq-spawn`.
- [x] Обе с зелёным гейтом `cargo build`+`cargo test` (build/test=True/True), без таймаутов.
- [x] Лимит параллелизма (`--limit 2`) и пер-job таймаут — через **processkit** (`output_all` + `.timeout` + kill-on-drop дерева); overlap ≈1.19× (ProcessKit-rs полностью оверлапнул сборку agent-workspace).
- [x] Изоляция обоих репо: main working copy не затронут, smoke-файлы только в workspace; pre-existing `weak-wave` цел.
- [x] `-AbandonRun` очистил обе workspace; репо вернулись к baseline.

## Реализация
`bin/hq-spawn/` (Rust на `processkit` 0.9.1 — догфуд: bounded fan-out + per-job timeout + kill-on-drop) +
`bin/exec-one.ps1` (lock-free исполнение одной задачи) + `bin/tick.ps1` (scheduler: lock, jobs.json → hq-spawn,
агрегат, `-AbandonRun`) + фикстура `_fixtures/sample-exec-task-2.md`. Прогон 2026-06-10, abandon (не лендили).

**Отклонения (зафиксировано):** processkit — Rust-библиотека → надзор реализован мини-бинарём `hq-spawn`
(а не из PowerShell). tessmux (PoC0) ещё не годен для live-грида → наблюдаемость = консоль + `_runs` + STATUS;
адопция tessmux/`ws` — позже.

## Зависимости
Только-после P2.
