---
repo: cSharp-repo-template
type: card
kind: template
language: C#/.NET
status: active
publishes: ["новые репо → NuGet.org"]
depends-on: [meta-repo-template]
depended-on-by: []
pair: null
updated: 2026-06-09
---

## Назначение
Публичный шаблон для создания новых C#/.NET репозиториев. Часто — source-of-truth общих
стандартов (`TEMPLATE-STANDARDS.md`). Токены `__ProjectName__`/`__Author__`/… заполняет `init`.

## Ответственность / границы
**Входит:** generic-скелет .NET-репо (`.slnx`, `Directory.Build/Packages.props`, AOT-настройки,
CI/CodeQL/release, community-health, агентские доки). **НЕ входит:** наши локальные процессы.

## Публичный интерфейс / точки входа
`scripts/init.{ps1,sh}` (`--project-name` …), `.claude/settings.json.template` → `.json` при init,
release через `workflow_dispatch` + GitHub App bypass (`release-token-bypass.md`).

## Сборка и тесты (в сгенерированном репо)
`dotnet build __ProjectName__.slnx` / `dotnet test tests/__ProjectName__.Tests/...`.

## Связи
Создаётся из `meta-repo-template`. Пара паритета стандартов: fs/kt/rs.

## ПРАВИЛО публичности
Shipped-файлы остаются generic. `.hq`-интеграция — только в `CLAUDE.local.md` (git-ignored через
`.git/info/exclude`), не коммитится/не пушится. Детали и правило: `../../knowledge/templates.md`.

## Ссылки
`../../../.Templates/cSharp-repo-template/` (README, TEMPLATE.md, AGENTS.md), `../../../.Templates/TEMPLATE-STANDARDS.md`
