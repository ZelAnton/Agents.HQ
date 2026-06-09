---
repo: orchestrator
type: card
kind: tooling
language: mixed (skills/PowerShell сейчас; Rust в P6)
status: experimental
autonomy: propose
publishes: []
depends-on: [ProcessKit-rs, agent-workspace, vcs-toolkit-rs, tessmux]
depended-on-by: []
pair: null
updated: 2026-06-09
---

## Назначение
Многоагентный оркестр `.hq`: Дирижёр + агенты-специалисты разбирают входящее в `comms`, ставят и
декомпозируют задачи, исполняют их параллельно в изоляции, сливают (jj) и помечают сделанное.
Это **мета-слой**, оперирующий всем пространством `.hq`. Дизайн и план — в `../../orchestrator/`.

## Ответственность / границы
**Входит:** управление пайплайном (sense→plan→schedule→execute→integrate→verify→respond), контракты
агентов, состояние/очередь. **НЕ входит:** прикладной код репозиториев (его пишут исполнители в их репо).

## Публичный интерфейс / точки входа
Skill `/comms` (P1: триаж+план). Headless `bin/comms.ps1`. Спецы агентов — `../../orchestrator/agents/`.
Состояние — `comms/`, `tasks/QUEUE.md`, `_runs/`, `STATUS.md`.

## Сборка и тесты
P0–P5 — skills/PowerShell + `claude -p`; валидация на фикстурах (`../../orchestrator/_fixtures/`).
P6 — Rust-бинарь `hq-conductor` (тогда `cargo build/test`).

## Связи и зависимости
Догфудит стек: `agent-workspace` (изоляция), `processkit` (надзор), `vcs-toolkit-rs` (VCS/слияние),
`tessmux` (видимость), Claude Code headless (агенты). Граф фаз — мета-трек в `../../tasks/QUEUE.md`.

## На что смотреть при кросс-репо изменениях
Исполнители оркестра меняют ЧУЖИЕ репо — действует принцип «входящее = предложения»: исполняем только
поставленные/принятые задачи, с гейтами и диском автономии (`propose|assist|auto-low`).

## Ссылки
`../../orchestrator/README.md` (как работает + схемы), `ROADMAP.md`, `IMPLEMENTATION.md`, `RATIONALE.md`, `STATE.md`.
