---
repo: ProcessGroup
type: card
kind: library
language: C#/.NET
status: active
publishes: [NuGet (уточнить имя пакета)]
depends-on: []
depended-on-by: [ProcessKit]
pair: ProcessKit-rs (косвенно, через ProcessKit)
updated: 2026-06-09
---

## Назначение
Кросс-платформенное управление временем жизни дочерних процессов для .NET: при выходе
родителя дочернее дерево гарантированно завершается (Windows Job Objects, POSIX process groups).
.NET 10, AOT-совместима, без внешних рантайм-зависимостей.

## Ответственность / границы
**Входит:** примитивы lifetime/containment дерева процессов.
**НЕ входит:** запуск процессов, стриминг вывода, runner — это `ProcessKit`.

## Публичный интерфейс / точки входа
Контейнер группы процессов с kill-on-exit семантикой (Job Object / process group).

## Сборка и тесты
```
dotnet build
dotnet test tests/ProcessGroup.Tests/ProcessGroup.Tests.csproj
pwsh scripts/test-linux.ps1
```

## Связи и зависимости
Фундамент .NET-линии: `ProcessGroup → ProcessKit → vcs-toolkit-dotNet → vcs-flow-dotnet`.

## На что смотреть при кросс-репо изменениях
Изменение поведения lifetime ломает `ProcessKit` и всех его потребителей вверх по графу —
заводи задачи с `depends-on` на потребителей. См. `../../knowledge/dependency-graph.md`.

## Ссылки
- `../../../ProcessGroup/README.md`, `../../../ProcessGroup/AGENTS.md`
