# QUEUE — единый индекс всех задач

Единственное место, где видно **последовательность, приоритеты и зависимости** всех задач
(и кросс-репо, и single-repo) сразу. Правила — в [`README.md`](README.md).

Обновлено: 2026-06-09

## Активные задачи

| ID | Scope | Приоритет | Статус | Repos | depends-on | parallel-safe-with | Спека |
|----|-------|-----------|--------|-------|------------|--------------------|-------|
| TASK-0001 | vcs-toolkit-rs | P1 | queued | vcs-toolkit-rs | — | TASK-0003 | `../projects/vcs-toolkit-rs/tasks/TASK-0001-processkit-0.8-adoption.md` |
| TASK-0002 | vcs-flow-rs | P1 | queued | vcs-flow-rs | TASK-0001 | TASK-0003 | `../projects/vcs-flow-rs/tasks/TASK-0002-processkit-0.8-adoption.md` |
| TASK-0003 | agent-workspace | P1 | queued | agent-workspace | — | TASK-0001, TASK-0002 | `../projects/agent-workspace/tasks/TASK-0003-processkit-0.8-adoption.md` |
| TASK-0004 | cross | P2 | queued | (вся линия + tessmux) | — | TASK-0001..0003 | `TASK-0004-push-to-main-to-pr-workflow.md` |

## Волны выполнения

Группировка по готовности. Внутри волны — параллельно; следующая волна стартует после
завершения зависимостей из предыдущей.

- **Волна 1 (нет зависимостей):** `TASK-0001`, `TASK-0003`, `TASK-0004` — параллельно.
- **Волна 2 (after Волна 1):** `TASK-0002` (only-after `TASK-0001`).

## Правила (кратко)
1. `status: ready` — все `depends-on` выполнены (`done`). Только такие берутся в работу.
2. Перед стартом — claim: `in-progress` + `assigned-to`.
3. Внутри волны задачи без общих файлов помечай `parallel-safe-with`.
4. Порядок сборки между репо см. в [`../knowledge/dependency-graph.md`](../knowledge/dependency-graph.md)
   — он определяет, какие кросс-репо задачи обязаны идти строго после каких.
5. Завершил → `done` + перенос спеки в `_archive/`.
