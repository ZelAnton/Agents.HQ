# QUEUE — единый индекс всех задач

Единственное место, где видно **последовательность, приоритеты и зависимости** всех задач
(и кросс-репо, и single-repo) сразу. Правила — в [`README.md`](README.md).

Обновлено: 2026-06-10 (P5 done)

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

## Мета-трек: оркестратор (P0–P6)

Оркестр строит сам себя. Спеки — в `../orchestrator/tasks/`. Дизайн — `../orchestrator/{ROADMAP,IMPLEMENTATION}.md`.
Трек **строго последовательный** (только-после); параллелить между фазами не нужно.

| ID | Фаза | scope | Статус | depends-on | Спека |
|----|------|-------|--------|------------|-------|
| TASK-0011 | P0 фундамент | orchestrator | **done** | — | `../orchestrator/tasks/TASK-0011-p0-foundations.md` |
| TASK-0012 | P1 триаж+план | orchestrator | **done** | TASK-0011 | `../orchestrator/tasks/TASK-0012-p1-triage-planner.md` |
| TASK-0013 | P2 1 задача в изоляции | orchestrator | **done** | TASK-0012 | `../orchestrator/tasks/TASK-0013-p2-single-execution.md` |
| TASK-0014 | P3 кросс-репо ∥ | orchestrator | **done** | TASK-0013 | `../orchestrator/tasks/TASK-0014-p3-cross-repo-parallel.md` |
| TASK-0015 | P4 jj-интеграция + авто-land | orchestrator | **done** | TASK-0014 | `../orchestrator/tasks/TASK-0015-p4-jj-integration-autoland.md` |
| TASK-0016 | P5 внутри-репо ∥ | orchestrator | **done** | TASK-0015 | `../orchestrator/tasks/TASK-0016-p5-intra-repo-parallel.md` |
| TASK-0017 | P6 hardening/scale | orchestrator | **ready** | TASK-0016 | `../orchestrator/tasks/TASK-0017-p6-hardening-scale.md` |

Следующая готовая: **TASK-0017 (P6)** — зависимость (P5) выполнена.
*(Номера 0005–0010 использованы примером валидационной фикстуры в `../orchestrator/_runs/` и в очередь НЕ входят.)*

## Правила (кратко)
1. `status: ready` — все `depends-on` выполнены (`done`). Только такие берутся в работу.
2. Перед стартом — claim: `in-progress` + `assigned-to`.
3. Внутри волны задачи без общих файлов помечай `parallel-safe-with`.
4. Порядок сборки между репо см. в [`../knowledge/dependency-graph.md`](../knowledge/dependency-graph.md)
   — он определяет, какие кросс-репо задачи обязаны идти строго после каких.
5. Завершил → `done` + перенос спеки в `_archive/`.
