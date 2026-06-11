---
name: hq-resume
description: Возобновить автономный диспетчер .hq — выставить paused=false в automation.json. Источник правды — .hq/orchestrator/skills/hq-resume/SKILL.md.
---

# `/hq-resume` — возобновить диспетчер .hq

Выставляет `paused: false` в `orchestrator/automation.json`. После этого `hq-conductor tick`
и `/hq-tick` снова спавнят воркеров при наличии готовых задач.

Источник правды: `.hq/orchestrator/skills/hq-resume/SKILL.md`.
Все пути — **относительные** от cwd (`d:/GitHub/Personal`).

## Жёсткие правила

- **Только один флаг.** Мутируешь только поле `paused` в `automation.json`. Не трогаешь лимиты,
  не изменяешь задачи или сессии.
- **Сохранить остальные поля.** Прочитай файл, обнови `paused: false`, запиши обратно.

## Шаги

**1. Прочитай `automation.json`.**
Путь: `.hq/orchestrator/automation.json`. Если файл не существует — создай с дефолтами:
`{paused: false, max_plan: 1, max_exec: 2, max_review: 1, autonomy: "auto-low"}`.

**2. Установи `paused: false`** и запиши файл обратно (JSON с отступами 2 пробела).

**3. Отчёт.**
```
Диспетчер возобновлён.
automation.json: paused=false
Запусти /hq-tick для немедленного тика или дожди следующего /loop-цикла.
```
