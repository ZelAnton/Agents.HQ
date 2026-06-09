---
type: knowledge
topic: orchestrator-state
updated: 2026-06-09
---

# Состояние Дирижёра — форматы и правила

Всё состояние оркестра — это файлы в `.hq` (в git). Здесь — конкретные форматы, дополняющие
псевдокод в [`IMPLEMENTATION.md §2`](IMPLEMENTATION.md). Контракты данных — в [`schemas/`](schemas/).

## Единственный писатель + лок
- Очередь `tasks/QUEUE.md` и статусы задач пишет **только Дирижёр**. Субагенты (triage/planner/exec)
  возвращают результат; применяет его Дирижёр.
- На время тика Дирижёр держит лок-файл **`.hq/orchestrator/.lock`** (git-ignored). Один активный тик.
  Стейл-лок (старше TTL) снимается при старте после проверки, что процесс мёртв.

## Журнал тиков — `tasks/_runs/<run_id>/`
- `run_id`: `YYYYMMDD-HHMM-tick` (live/dry-run) или `fixture-YYYYMMDD-HHMM` (валидация на фикстуре).
- `tick.json` — по схеме [`schemas/tick-log.schema.json`](schemas/tick-log.schema.json): что просмотрено,
  пропущено, как оттриажено, что заплан��ровано, ошибки.
- `triage/<item>.json` — сырой структурный выход triage по элементу (по `triage.schema.json`).
- `plan/<seed>.json` — выход planner (по `planner.schema.json`).
- `<TASK>.result.json` — выход исполнителя (с P2, по `executor-result.schema.json`).
- В режимах `dry-run`/`fixture` Дирижёр пишет **только** в `_runs/<run_id>/` и НЕ трогает реальные
  `comms`/`tasks/QUEUE.md` (предлагаемые правки складывает рядом как `proposed-*`).

## Поля claim в спеке задачи (frontmatter)
Добавляются Дирижёром при взятии задачи в работу (с P2; в P1 не используются):
```yaml
assigned-to: <agent-id|null>   # кто исполняет
claimed-at: <ISO|null>         # когда взято
lease-until: <ISO|null>        # TTL лизы; истекла без done → задача снова ready
```

## Дашборд — `orchestrator/STATUS.md`
Генерируется Дирижёром в конце тика из `QUEUE.md` + последнего `tick.json`. Человеко-читаемая
сводка: активные/ready/blocked/escalated, последний тик, метрики. Шаблон — `STATUS.template.md`.

## Уровень автономии репозитория — `autonomy`
В `projects/<repo>/card.md` (frontmatter). Значения:
- `propose` — оркестр только предлагает (триаж+план+черновики); приземляет человек. **Default при отсутствии поля.**
- `assist` — исполняет в изоляции и готовит к приземлению, но land — за человеком.
- `auto-low` — низкорисковое приземляет сам после зелёного гейта; рисковое → `human/DEC`.
Дирижёр читает поле; отсутствует ⇒ `propose` (самое консервативное). Массовая простановка не нужна.

## Исключения обработки
Конфиг тика держит список входящих, которые Дирижёр **пропускает** (`skip`). Сейчас в нём —
`T-20260609-vcs-processkit-feedback` (по решению: не обрабатываем). Альтернатива — поле
`orchestrator: skip` во frontmatter треда (не используем, чтобы не править реальный тред).
