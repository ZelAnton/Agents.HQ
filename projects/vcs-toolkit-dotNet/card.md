---
repo: vcs-toolkit-dotNet
type: card
kind: library
language: C#/.NET
status: active
publishes: ["NuGet: Vcs.Git", "NuGet: Vcs.Jujutsu", "NuGet: Vcs.GitHub"]
depends-on: [ProcessKit]
depended-on-by: [vcs-flow-dotnet]
pair: vcs-toolkit-rs
updated: 2026-06-09
---

## Назначение
.NET-тулкит из трёх независимых библиотек для автоматизации Git, Jujutsu и GitHub через
драйв их CLI как дочерних процессов — типизировано, async, тестируемо. .NET 10, AOT-совместимо.

## Ответственность / границы
**Входит:** типизированные обёртки команд Git/jj/GitHub.
**НЕ входит:** workflow-сценарии → `vcs-flow-dotnet`; запуск процессов → `ProcessKit`.

## Публичный интерфейс / точки входа
Интерфейсы `IGitCli`, `IJujutsuCli`, `IGitHubCli`. Три отдельных NuGet-пакета.

## Сборка и тесты
```
dotnet build Vcs.slnx
dotnet test Vcs.slnx
pwsh scripts/test-linux.ps1
pwsh scripts/test-aot.ps1
```

## Связи и зависимости
Поверх `ProcessKit`. Потребитель — `vcs-flow-dotnet`. Пара паритета — `vcs-toolkit-rs`
(в Rust-версии больше форджей: +GitLab, +Gitea).

## На что смотреть при кросс-репо изменениях
Изменение API обёрток затрагивает `vcs-flow-dotnet`. Паритет фич — с `vcs-toolkit-rs`.

## Ссылки
- `../../../vcs-toolkit-dotNet/README.md`, `../../../vcs-toolkit-dotNet/AGENTS.md`, `../../../vcs-toolkit-dotNet/ROADMAP.md`
- `../../../vcs-toolkit-dotNet/docs/linux-testing.md`
