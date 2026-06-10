---
name: add-task
description: Добавить новую задачу в очередь intake (.hq). Создаёт task-спеку со status:intake и строку в QUEUE.md. Источник правды — .hq/orchestrator/skills/add-task/SKILL.md (после правок — install-skill.ps1).
---

# `/add-task` — добавить задачу в очередь intake

Ты — **Дирижёр** оркестра `.hq`. Детерминированную логику делаешь САМ; LLM-суждения (оценка,
планирование) — это работа `/comms` (triage+plan), не этого скилла. Здесь только: принять постановку,
присвоить ID, записать спеку, добавить строку в QUEUE.md.

Источник правды — `.hq/orchestrator/skills/add-task/SKILL.md`.
Headless-эквивалент: `.hq/orchestrator/bin/add-task.ps1`.
Все пути — **относительные** от cwd (`d:/GitHub/Personal`).

## Аргументы (из запроса пользователя)

Пользователь описывает задачу свободным текстом. Из текста извлеки:
- `title` — краткое название (1 строка)
- `body` — исходный текст постановки (verbatim или краткий парафраз)
- `priority` — P0 | P1 | P2 (если не указано явно — P2)
- `scope` — `cross` или имя репо (если не указано — `cross`)
- `repos` — список затронутых репо (если не указано — `[orchestrator]`)

## Жёсткие правила

- **Лок (единственный писатель).** Под локом `.hq/orchestrator/.lock` (PID+ISO, TTL 30м, проверь
  жив ли процесс); если занят — сообщи пользователю и не продолжай.
- **Только intake.** Не запускать triage/planning — это `/comms`. Только создать запись.
- **Скан утечек.** Перед записью: regex `[A-Za-z]:[\\/](GitHub|Users)`, `/Users/`, `ghp_`, `AKIA`.
  Совпадение в тексте задачи → заблокировать и сообщить.
- **Idempotency.** Не создавать дублей: если задача с таким же title уже есть в QUEUE.md с
  `status:intake` — сообщи об этом и предложи использовать существующую.

## Шаги

**0. Лок.** Создай `.hq/orchestrator/.lock` с `<PID>\t<ISO>`. Если лок существует и не стейл
(TTL 30м + PID жив) — сообщи "лок активен, попробуй позже" и завершись.

**1. Следующий ID (детерминированно).** Считай все `TASK-####` в `.hq/tasks/QUEUE.md`
(обе таблицы). `next_id = max(####) + 1` (4 цифры, leading zeros). Если QUEUE.md недоступен —
сообщи об ошибке и завершись (не угадывать ID).

**2. Скан утечек.** Прогони regex по `title` + `body`. Совпадение → блок.

**3. Создать спеку задачи.** Файл `.hq/orchestrator/tasks/TASK-NNNN-<slug>.md` (slug = title
kebab-case, max 40 символов, ASCII). Шаблон из `.hq/_templates/task.md`. Frontmatter:
- `id`: TASK-NNNN
- `status`: intake
- `created-by`: human
- `date`: сегодня (YYYY-MM-DD)
- `priority`: из запроса
- `scope`: из запроса или `cross`
- `repos`: из запроса или `[orchestrator]`
- `depends-on`: []
- `parallel-safe-with`: []
- `assigned-to`: null
- `origin`: human
- `risk`: null
- `fix-attempt`: 0
- `session`: null
Тело: `## Цель\n<body>\n\n## Объём по репозиториям\n<repos если известны>\n\n## Критерии готовности (DoD)\n- [ ] (ожидает планировщика)\n\n## Риски / зависимости\n(ожидает планировщика)`.

**4. Добавить строку в QUEUE.md.** В раздел «Активные задачи» добавь строку:
`| TASK-NNNN | <scope> | <priority> | intake | <repos-list> | — | — | <путь к спеке> |`
Обнови строку «Обновлено: YYYY-MM-DD».

**5. Отчёт.** Кратко:
```
Задача добавлена: TASK-NNNN — <title>
Статус: intake (ожидает триажа — запусти /comms чтобы спланировать)
Спека: .hq/orchestrator/tasks/TASK-NNNN-<slug>.md
```

**6. Снять лок** (даже при ошибке).
