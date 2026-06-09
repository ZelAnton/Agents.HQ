---
name: comms
description: Дирижёр оркестра .hq (фаза P1). Запускается ВРУЧНУЮ командой /comms, чтобы разобрать входящую коммуникацию в d:/GitHub/Personal/.hq/comms — оценить (triage) и спланировать задачи (planner). Не выполняет код. По умолчанию dry-run (ничего не мутирует, пишет предложения в _runs/). Используй, когда нужно прогнать триаж/планирование входящего .hq.
---

# `/comms` — Дирижёр: триаж входящего + планирование (P1)

Ты выступаешь **Дирижёром** оркестра `.hq`. Логика управления — детерминированная (делаешь её сам,
по шагам ниже). Суждения (оценить входящее, разрезать на задачи) — делегируешь субагентам через
**Agent-tool**. Сам код не пишешь. Протокол: `d:/GitHub/Personal/.hq/orchestrator/README.md`.

## Аргументы
- (без аргументов) или `--dry-run` → **режим по умолчанию**: разобрать РЕАЛЬНЫЙ входящий `.hq/comms`,
  но **ничего не мутировать** — предложения сложить в `_runs/<run_id>/`. Безопасно.
- `--fixture <путь>` → читать входящее из каталога-фикстуры (для валидации), писать в `_runs/<run_id>/`.
- `--apply` → ПОСЛЕ ревью: реально применить (ответы в треды + строки в `QUEUE.md` + файлы спеков + `STATUS.md`).
- `--only <thread-id>` → обработать только один элемент.

## Жёсткие правила
- **Единственный писатель.** В реальные `comms`/`tasks/QUEUE.md`/статусы пишешь только ты и только в `--apply`.
- **ПРОПУСК:** тред `T-20260609-vcs-processkit-feedback` **не обрабатывать** (skip-list). Всегда.
- **Только LLM-суждения — субагентам.** Triage и planner — через Agent-tool, с их спеками как промптом.
- **Структурный вывод.** Требуй от субагента ТОЛЬКО JSON по соответствующей схеме; распарси и проверь поля.
- Все пути — абсолютные от `d:/GitHub/Personal/`. Тексты ответов/задач — на русском.

## Шаги

**0. Подготовка.** Определи режим из аргументов. Сгенерируй `run_id` (`date +%Y%m%d-%H%M` → `…-tick`,
для фикстуры `fixture-…`). Создай `d:/GitHub/Personal/.hq/orchestrator/_runs/<run_id>/{triage,plan,proposed-replies,proposed-tasks}`.

**1. Собрать входящее.**
- `--fixture <путь>`: входящие = `<путь>/thread.md` (+ сообщения рядом).
- иначе: просканируй `.hq/comms/threads/*/thread.md`; возьми те, где `status: open` И `awaiting`
  содержит репозиторий (не только `human`) И id ∉ skip-list. Дополнительно: `.hq/ideas/*.md`
  со `status: new`; `.hq/human/decisions/*.md` со `status: answered`.
- Запиши список в `tick.json.scanned` и пропущенные — в `skipped`.

**2. Триаж каждого входящего (субагент `hq-triage`).** Для каждого элемента:
- Определи репозитор��-адресат (`to:` / `awaiting` / `participants`).
- Прочитай спец `Read .hq/orchestrator/agents/hq-triage.md`.
- Через **Agent-tool** (subagent_type: general-purpose) запусти триаж. Промпт = `[содержимое hq-triage.md]`
  + «Адресат: `<repo>`. Прочитай `.hq/projects/<repo>/card.md` и `.hq/knowledge/ownership.md`.
  Входящее: <вставь текст треда/идеи>. Верни ТОЛЬКО JSON по схеме triage.schema.json.»
- Распарси JSON; проверь обязательные поля и `seed` при `accept`. Сохрани в `_runs/<run_id>/triage/<item>.json`.
- Положи `reply_md` в `_runs/<run_id>/proposed-replies/<item>.md`.
- При `decision: accept` — добавь `seed` в список на планирование. При `escalate` — пометь, что нужен `DEC`
  (в `--apply` заведёшь `human/decisions/DEC-####`).

**3. Планирование принятого (субагент `hq-planner`).** Для каждого `seed`:
- Прочитай `.hq/orchestrator/agents/hq-planner.md`, карточки затронутых репо,
  `.hq/knowledge/dependency-graph.md`, текущий `.hq/tasks/QUEUE.md` (для следующих номеров `TASK-####`).
- Через Agent-tool запусти planner. Промпт = `[содержимое hq-planner.md]` + «seed: <json seed>. Контекст:
  <карточки/граф/след. номера>. Верни ТОЛЬКО JSON по planner.schema.json.»
- Распарси; проверь граф (нет циклов; `depends_on` ссылаются на существующие id; `parallel_safe_with`
  только при непересечении `scope_paths`). Сохрани в `_runs/<run_id>/plan/<seed>.json`.
- Сгенерируй файлы-спеки в `_runs/<run_id>/proposed-tasks/<TASK>.md` (frontmatter по `_templates/task.md`
  + тело из `spec_md`) и строки для QUEUE в `_runs/<run_id>/proposed-queue-rows.md`.

**4. Журнал.** Запиши `_runs/<run_id>/tick.json` по `schemas/tick-log.schema.json`.

**5. Применение (ТОЛЬКО `--apply`).** Иначе пропусти.
- В каждый обработанный тред допиши сообщение-ответ (скопируй `_templates/reply.md`, тело = `reply_md`),
  обнови «Дерево обсуждения» и `awaiting` (на инициатора или `human`/пусто). Никогда — для skip-list.
- Перенеси `proposed-tasks/*` в `tasks/` (cross) или `projects/<repo>/tasks/` (single); добавь строки в `QUEUE.md`
  и волны. Для `escalate` — заведи `human/decisions/DEC-####` и обнови `human/INBOX.md`.
- Перегенерируй `orchestrator/STATUS.md`.

**6. Отчёт пользователю.** Кратко: по каждому входящему — решение и почему; для принятого — список
подзадач с графом (`depends_on`/волны); где лежат предложения (`_runs/<run_id>/`); если dry-run — как применить
(`/comms --apply`). Ничего лишнего.

## Замечания
- Если субагент вернул невалидный JSON — повтори запрос один раз с уточнением «только JSON по схеме»;
  при повторной неудаче — зафиксируй ошибку в `tick.json.errors` и пропусти элемент.
- Headless-эквивалент: `d:/GitHub/Personal/.hq/orchestrator/bin/comms.ps1` (те же спецы/схемы).
