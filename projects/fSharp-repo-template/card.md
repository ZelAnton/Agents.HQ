---
repo: fSharp-repo-template
type: card
kind: template
language: F#/.NET
status: active
publishes: ["новые репо → NuGet.org"]
depends-on: [meta-repo-template]
depended-on-by: []
pair: null
updated: 2026-06-09
---

## Назначение
Публичный шаблон для создания новых F#/.NET репозиториев. Generic-скелет, аналогичный
`cSharp-repo-template`, с F#-спецификой.

## Ответственность / границы
**Входит:** generic F#-репо (`.fsproj`/`.slnx`, центральные деп-версии, CI/release, Fantomas,
community-health, агентские доки). **НЕ входит:** наши локальные процессы.

## Публичный интерфейс / точки входа
`scripts/init.{ps1,sh}`, release `workflow_dispatch` + App bypass. **Без CodeQL** — у CodeQL нет
F#-экстрактора (документировано в `TEMPLATE-STANDARDS.md`).

## Сборка и тесты (в сгенерированном репо)
`dotnet build` / `dotnet test` (как в .NET-линии).

## Связи
Создаётся из `meta-repo-template`. Паритет стандартов: cs/kt/rs.

## ПРАВИЛО публичности
Shipped-файлы generic. `.hq`-интеграция — только в `CLAUDE.local.md` (git-ignored). См. `../../knowledge/templates.md`.

## Ссылки
`../../../.Templates/fSharp-repo-template/`, `../../../.Templates/TEMPLATE-STANDARDS.md`
