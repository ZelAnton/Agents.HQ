---
name: hq-tick
description: Запустить один тик диспетчера .hq (hq-conductor tick --mode auto-low) с лимитами из automation.json. Используй как тело /loop /hq-tick для автономного режима. Все пути — относительные от cwd (d:/GitHub/Personal).
---

# `/hq-tick` — один тик диспетчера .hq

Запускает один прогон диспетчера через headless-обёртку `bin/hq-tick.ps1`, которая читает
лимиты/паузу из `automation.json` и вызывает `hq-conductor tick`. Это детерминированный тик
(не LLM): recovery → promote → dispatch plan/exec/review → land/escalate.

Источник правды: `.hq/orchestrator/skills/hq-tick/SKILL.md`.
Headless-эквивалент: `.hq/orchestrator/bin/hq-tick.ps1`.
Все пути — **относительные** от cwd (`d:/GitHub/Personal`); абсолютов не хардкодим.

## Аргументы (опциональные)

Без аргументов — тик `auto-low` с лимитами из `automation.json`. Опционально:
- `--mode <mock|assist|auto-low>` → `-Mode` обёртки (по умолчанию `auto-low`).
- `--max-plan N`, `--max-exec N`, `--max-review N` → одноимённые параметры обёртки
  (переопределяют значения из `automation.json`).

## Жёсткие правила

- **Один тик — один запуск.** Скилл не управляет паузами и не правит `automation.json`.
  Для паузы — `/hq-pause`; для статуса — `/hq-status`.
- **Пауза уважается.** Обёртка сама выходит, если `automation.json` `paused=true` (и conductor
  тоже проверяет). Ничего дополнительно делать не нужно.
- **Продуктовые репо не трогаем.** Exec диспатчится только для задач с `autonomy: auto-low`;
  `owner: human`-задачи исключены из всех ролей. Защита — в conductor (autonomy gate +
  `is_human_owned`), не в этом скилле.

## Шаги

**1. Запусти обёртку** через Bash/PowerShell (cwd = `d:/GitHub/Personal`):
```powershell
pwsh -NoProfile -File .hq/orchestrator/bin/hq-tick.ps1 -Mode auto-low
```
Добавь `-MaxPlan/-MaxExec/-MaxReview N`, только если пользователь задал лимиты явно.
Захвати stdout + stderr и exit code.

**2. Отчёт.** Кратко разбери вывод тика:
```
Тик: <run_id>  режим: <mode>
  planned: N  exec: N  reviewed: N
  [строки recovery / fix-requeue / exec-skip / promote / review→… если были]
```
Первая строка вывода — `tick: run=TICK-… mode=…`; итог — `tick done…: planned=… exec=… reviewed=…`.
Если обёртка напечатала `hq-tick: paused …` — сообщи, что тики приостановлены (`/hq-resume` чтобы снять).
Если exit code ≠ 0 — покажи stderr полностью (crash-safe: следующий тик доведёт через recovery,
но пользователь должен знать о сбое).

## Использование в `/loop`

`/loop /hq-tick` запускает этот скилл по расписанию. Каждая итерация выполняет шаги 1–2.
Если обёртка вышла по паузе (`paused=true`) — итерация завершается штатно (не падает),
`/loop` продолжит опрашивать. Управление расписанием — на стороне `/loop`; вручную
`ScheduleWakeup` дёргать не нужно.
