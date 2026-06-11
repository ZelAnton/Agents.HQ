---
name: hq-pause
description: Приостановить автономный диспетчер .hq — выставить paused=true в automation.json. Активные сессии/агенты доживают; новые спавны прекращаются. Источник правды — .hq/orchestrator/skills/hq-pause/SKILL.md.
---

# `/hq-pause` — приостановить диспетчер .hq

Выставляет `paused: true` в `orchestrator/automation.json`. Тик (`hq-conductor tick`) и
`/hq-tick` проверяют этот флаг в начале и не спавнят новые воркеры при `paused=true`.
**Активные сессии не убиваются** — они доживают до своего завершения.

Источник правды: `.hq/orchestrator/skills/hq-pause/SKILL.md`.
Все пути — **относительные** от cwd (`d:/GitHub/Personal`).

## Жёсткие правила

- **Только один флаг.** Мутируешь только поле `paused` в `automation.json`. Не трогаешь лимиты,
  не трогаешь активные задачи или сессии.
- **Сохранить остальные поля.** Прочитай файл, обнови `paused: true`, запиши обратно (JSON pretty).

## Шаги

**1. Прочитай `automation.json`.**
Путь: `.hq/orchestrator/automation.json`. Если файл не существует — создай с дефолтами:
`{paused: true, max_plan: 1, max_exec: 2, max_review: 1, autonomy: "auto-low"}`.

**2. Установи `paused: true`** и запиши файл обратно (JSON с отступами 2 пробела).

**3. Проверь активные сессии (информационно).** Посмотри `.hq/orchestrator/sessions/active/`.
Если есть активные — сообщи их число (они не убиваются, только новые спавны остановлены).

**4. Отчёт.**
```
Диспетчер приостановлен.
automation.json: paused=true
Активные сессии: N (не прерваны, доживают до завершения)
Возобнови: /hq-resume
```
