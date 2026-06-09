---
repo: vcs-flow-dotnet
type: card
kind: cli
language: C#/.NET
status: active
publishes: [Native-AOT исполняемые команды]
depends-on: [ProcessKit, vcs-toolkit-dotNet]
depended-on-by: []
pair: vcs-flow-rs
updated: 2026-06-09
---

## Назначение
Объединённые workflow-команды для git/jujutsu (`commit`, `push`, …), каждая — Native-AOT
исполняемый файл, ведущий многошаговые VCS-операции за интерактивным UI (Spectre.Console).

## Ответственность / границы
**Входит:** сценарии workflow (последовательности операций), интерактивный UX.
**НЕ входит:** примитивы CLI Git/jj/GitHub → `vcs-toolkit-dotNet`; запуск → `ProcessKit`.

## Публичный интерфейс / точки входа
Команды-исполняемые (`Vcs.Flow.Commit` и т.д.). Решение `Vcs.Flow.slnx`.

## Сборка и тесты
```
dotnet build Vcs.Flow.slnx
dotnet test Vcs.Flow.slnx
dotnet publish src/Vcs.Flow.Commit/Vcs.Flow.Commit.csproj -c Release
```

## Связи и зависимости
Поверх `ProcessKit` (сейчас шеллит через него; мигрирует на типы `vcs-toolkit-dotNet` после
публикации в NuGet). Пара паритета — `vcs-flow-rs` (Rust-версия более зрелая: ratatui TUI, все фичи).

## На что смотреть при кросс-репо изменениях
Зависит от API `vcs-toolkit-dotNet`/`ProcessKit`. Паритет UX/фич — с `vcs-flow-rs`.

## Ссылки
- `../../../vcs-flow-dotnet/README.md`, `../../../vcs-flow-dotnet/AGENTS.md`
