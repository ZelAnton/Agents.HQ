# MIGRATION — перенос существующих записей в `.hq`

Карта переноса разрозненных untracked-заметок из корня `d:\GitHub\Personal\` и `Ideas/`
в централизованную модель `.hq`. Tracked-доки внутри репозиториев (`*/ROADMAP.md`, `*/docs/*`)
**не переносились** — на них ссылаются карточки `projects/<repo>/card.md`.

Дата миграции: 2026-06-09.

## Перенесённые файлы

| Старый путь (от `d:\GitHub\Personal\`) | Новый путь (в `.hq/`) | Тип |
|---|---|---|
| `ROADMAP.md` (processkit-py roadmap) | `projects/processkit-py/ROADMAP.md` | no-repo-yet roadmap |
| `Ideas/Roadmaps/processkit-py.md` | `projects/processkit-py/knowledge/roadmap-py-ideas-variant.md` | вариант roadmap (свести с каноном при ревью) |
| `Ideas/Roadmaps/processkit-go.md` | `projects/processkit-go/ROADMAP.md` | no-repo-yet roadmap |
| `Ideas/Requests/processkit-client-cancellation-spec.md` | `projects/ProcessKit-rs/ideas/processkit-client-cancellation-spec.md` | идея/спека (single-repo) |
| `processkit-streaming-spec.md` | `projects/ProcessKit-rs/knowledge/streaming-spec.md` | спека |
| `ProcessKit-rs-implementation-intentions.md` | `projects/ProcessKit-rs/knowledge/implementation-intentions.md` | заметки реализации |
| `processkit-0.8-instructions-vcs-toolkit-rs.md` | `projects/vcs-toolkit-rs/tasks/processkit-0.8-adoption.md` | → `TASK-0001` |
| `processkit-0.8-instructions-vcs-flow-rs.md` | `projects/vcs-flow-rs/tasks/processkit-0.8-adoption.md` | → `TASK-0002` |
| `processkit-0.8-instructions-agent-workspace.md` | `projects/agent-workspace/tasks/processkit-0.8-adoption.md` | → `TASK-0003` |
| `process-ideas.md` | `knowledge/research/processkit-competitor-shortlist.md` | research |
| `processkit-competitive-analysis.md` | `knowledge/research/processkit-competitive-analysis.md` | research |
| `release-token-bypass.md` | `knowledge/howto/release-token-bypass.md` | howto |
| `rewrite-push-to-main-to-pr-workflow.md` | `tasks/_src-push-to-main-to-pr-workflow.md` | → `TASK-0004` |

## Заведённые из миграции артефакты

- `TASK-0001` (vcs-toolkit-rs), `TASK-0002` (vcs-flow-rs, after 0001), `TASK-0003` (agent-workspace, ∥ 0001)
  — переход на ProcessKit 0.8. Индекс — в [`tasks/QUEUE.md`](tasks/QUEUE.md).
- `TASK-0004` (cross) — миграция push-to-main → PR workflow.

## Намеренно НЕ перенесено

- `ProcessKit/ROADMAP.md`, `ProcessKit-rs/ROADMAP.md`, `vcs-toolkit-rs/ROADMAP.md` и все `*/docs/*`
  — tracked-доки репозиториев; карточки на них ссылаются.
- `Process-ideas-repos/` — клоны чужих репо (внешний research); остаётся на месте.
- `Safe/` — бэкап планов tessmux; остаётся на месте.
- `.Templates/` — шаблоны репо (в т.ч. свой `release-token-bypass.md`); остаётся на месте.

## Примечания
- `Ideas/Roadmaps/` и `Ideas/Requests/` опустели после переноса; сама `Ideas/` оставлена пустой
  (можно использовать дальше под продуктовые roadmap'ы или удалить).
- Корень `d:\GitHub\Personal\` очищен от бродячих `*.md` (кроме самих репозиториев).
