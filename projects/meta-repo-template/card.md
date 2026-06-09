---
repo: meta-repo-template
type: card
kind: meta-template
language: (мета)
status: active
publishes: ["порождает <lang>-repo-template (не инициализируется напрямую)"]
depends-on: []
depended-on-by: [cSharp-repo-template, fSharp-repo-template, kotlin-repo-template, rust-repo-template, Go-repo-template, Python-repo-template, ts-repo-template]
pair: null
updated: 2026-06-09
---

## Назначение
**Шаблон для создания шаблонов** (`<lang>-repo-template`). НЕ инициализируется напрямую как проект.
Двух-токенная модель: `__ProjectName__`-токены проходят насквозь (в новые репо), `%%`-мета-токены
заполняются один раз при авторинге нового language-шаблона.

## Ответственность / границы
**Входит:** мета-скелет + `META-AUTHORING.md` (happy-path авторинга), generic CI/release/community-health
с `%%`-плейсхолдерами. **НЕ входит:** конкретный язык, наши локальные процессы.

## Публичный интерфейс / точки входа
`META-AUTHORING.md` (стартовая точка), `META:start…META:end` блок в README (удаляется при авторинге),
`%%LangVersion%%`/`%%RegistryName%%`/`%%FileExt%%`/… мета-токены. Есть `BUILD-SYSTEM.TODO.md`.

## Сборка и тесты
N/A напрямую — порождает language-шаблоны, которые уже собираются по-своему.

## Связи
Источник для всех `<lang>-repo-template`. При добавлении нового языка — начинать отсюда
(см. `META-AUTHORING.md`) и обновлять `TEMPLATE-STANDARDS.md`.

## ПРАВИЛО публичности
Shipped-файлы generic. `.hq`-интеграция — только в `CLAUDE.local.md` (git-ignored). См. `../../knowledge/templates.md`.

## Ссылки
`../../../.Templates/meta-repo-template/` (README, META-AUTHORING.md), `../../../.Templates/TEMPLATE-STANDARDS.md`
