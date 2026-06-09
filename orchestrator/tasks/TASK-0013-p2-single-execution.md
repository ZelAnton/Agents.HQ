---
id: TASK-0013
type: task
title: Оркестратор P2 — исполнение одной задачи в изоляции
date: 2026-06-09
scope: orchestrator
status: done
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
- [x] Подзадача выполнена в **изолированной jj-workspace** (`jj workspace add`); основной репо не затронут.
- [x] `cargo build` + `cargo test` зелёные как **авторитетный гейт** Дирижёра (не только self-report).
- [x] Изоляция доказана: main working copy ProcessKit-rs byte-identical базлайну; smoke-файл только в workspace.
- [x] Откат (`-Abandon`) очищает: workspace forgotten, изменение исчезло, репо чист.

## Реализация
`agents/hq-exec.md` + `bin/exec.ps1` + фикстура `_fixtures/sample-exec-task.md`. Прогон 2026-06-09 на
ProcessKit-rs (безопасная микро-задача, **abandon**, не лендили — по решению пользователя).

**Отклонение от плана (зафиксировано):** built `ws.exe` оказался stale (v0.13.18, CLI расходится с
текущим source). Вместо него P2 использует **`jj workspace add` напрямую** (тот же примитив изоляции,
версионно-независимо). Адопцию `ws` (CoW, auto-merge, tab) перенесли на P3+ (после ребилда).

## Зависимости
Только-после P1.
