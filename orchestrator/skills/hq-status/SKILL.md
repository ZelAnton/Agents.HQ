---
name: hq-status
description: Сводка состояния оркестратора .hq — счётчики задач по статусам, активные сессии, открытые DEC, блокировки, последние тики. Только чтение, не мутирует ничего. Источник правды — .hq/orchestrator/skills/hq-status/SKILL.md.
---

# `/hq-status` — состояние оркестратора .hq (read-only)

Ты — **Наблюдатель** оркестра `.hq`. Читаешь файлы, ничего не пишешь. Собираешь сводку:
счётчики задач по статусам, активные/stale сессии, открытые DEC, блокировки, automation.json,
последние прогоны тика. Источник правды: `.hq/orchestrator/skills/hq-status/SKILL.md`.

Все пути — **относительные** от cwd (`d:/GitHub/Personal`).

## Жёсткие правила

- **Только чтение.** Этот скилл не мутирует файлы, не запускает команды, не создаёт задачи.
- **Актуальные данные.** Читай файлы напрямую (через Read/Glob/Grep), не кешируй между вызовами.

## Шаги

**1. Automation.json.** Прочитай `.hq/orchestrator/automation.json`. Покажи: `paused`, лимиты
(`max_plan/exec/review`). Если файл не существует — показать "(нет файла, дефолты)".

**2. Счётчики задач.** Просканируй **все** задачи:
- `.hq/tasks/*.md` (TASK-*.md, type:task)
- `.hq/orchestrator/tasks/*.md`
- `.hq/projects/*/tasks/*.md`

Для каждой извлеки `status` из frontmatter. Сгруппируй и посчитай:
`intake / queued / ready / in-progress / in-review / fix-needed / blocked / escalated / done / cancelled / rejected`.

Дополнительно: покажи задачи в `in-progress`, `in-review`, `fix-needed`, `blocked`, `escalated`
с ID + title + scope (это рабочая очередь).

**3. Активные сессии.** Просканируй `.hq/orchestrator/sessions/active/SESS-*.md`.
Для каждой: `id`, `role`, `task`, `state`, `last-heartbeat` (если >10 мин назад — пометить ⚠ stale?),
`lease-until`. Если heartbeat старше lease — это кандидат для `doctor`.

**4. Открытые DEC (решения для человека).** Просканируй `.hq/human/decisions/DEC-*.md`
с `status: open`. Покажи: `id`, `title`, `created`, `risk-if-unanswered` (если есть).
Кол-во = review-backlog требующий человека.

**5. INBOX.** Прочитай `.hq/human/INBOX.md`. Посчитай строки `- [ ]` (непрочитанные).
Если >0 — показать число и первые 3 строки.

**6. Последние тики.** Прочитай `.hq/orchestrator/STATUS.md`. Извлеки строку «Последний тик»
и секцию «Метрики последних тиков» (последние 5 строк таблицы). Показать как есть.

**7. Automation-состояние.** Если `paused: true` — показать предупреждение `⛔ ТИКИ ПРИОСТАНОВЛЕНЫ`.
Если `paused: false` — показать `✓ тики активны`.

## Формат вывода

```
=== .hq STATUS ===

Automation: paused=<true/false>  max_plan=<N> max_exec=<N> max_review=<N>

Задачи (<N> итого):
  intake   N  |  queued  N  |  ready  N  |  in-progress  N
  in-review N |  fix-needed N |  blocked N  |  escalated N
  done    N   |  cancelled N  |  rejected N

Рабочая очередь:
  in-progress: TASK-XXXX (<title>) [<scope>]
  in-review:   TASK-XXXX (<title>) [<scope>]
  fix-needed:  (нет)
  blocked:     TASK-XXXX — <blocked-reason>
  escalated:   TASK-XXXX — <blocked-reason>

Активные сессии: N
  SESS-… | plan | TASK-XXXX | running | HB: <ago>
  (нет)

Открытые DEC: N
  DEC-… — <title> [<risk-if-unanswered>]

INBOX: N непрочитанных
  - [ ] …

Последний тик: <run_id>  <mode>  <time>
Метрики: (последние 5 строк из STATUS.md)

[⛔ ТИКИ ПРИОСТАНОВЛЕНЫ | ✓ тики активны]
```
