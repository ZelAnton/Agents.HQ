---
repo: ProcessKit
type: card
kind: library
language: C#/.NET
status: active
publishes: [NuGet (уточнить имя пакета)]
depends-on: [ProcessGroup]
depended-on-by: [vcs-toolkit-dotNet, vcs-flow-dotnet]
pair: ProcessKit-rs
updated: 2026-06-09
---

## Назначение
Управление дочерними процессами для .NET с двумя поверхностями: `ProcessGroup` (lifetime)
и `ProcessRunner`/`IProcessRunner` (async-запуск со стримингом stdout/stderr).
.NET 10, AOT-совместима, без внешних рантайм-зависимостей. Вытеснил внутренний прототип `vcs-process`.

## Ответственность / границы
**Входит:** запуск процессов, runner, стриминг, захват результата.
**НЕ входит:** примитивы lifetime → `ProcessGroup`; VCS-обёртки → `vcs-toolkit-dotNet`.

## Публичный интерфейс / точки входа
`IProcessRunner` (mock-seam), runner со стримингом, `ProcessGroup`. Потребляется
`vcs-flow-dotnet` и `vcs-toolkit-dotNet` как слой запуска.

## Сборка и тесты
```
dotnet build
dotnet test tests/ProcessKit.Tests/ProcessKit.Tests.csproj
dotnet publish tests/ProcessKit.AotSmoke/ProcessKit.AotSmoke.csproj -c Release -r linux-x64 -p:PublishAot=true
```

## Связи и зависимости
Поверх `ProcessGroup`. Пара паритета — `ProcessKit-rs`.

## На что смотреть при кросс-репо изменениях
Изменение API runner затрагивает `vcs-toolkit-dotNet`/`vcs-flow-dotnet`. Значимые фичи —
зеркаль в `ProcessKit-rs` (паритет). Порядок сборки см. `../../knowledge/dependency-graph.md`.

## Ссылки
- `../../../ProcessKit/README.md`, `../../../ProcessKit/AGENTS.md`, `../../../ProcessKit/ROADMAP.md`
- `../../../ProcessKit/docs/linux-testing.md`
