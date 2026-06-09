---
repo: kotlin-repo-template
type: card
kind: template
language: Kotlin/JVM
status: active
publishes: ["новые репо → Maven Central (Gradle)"]
depends-on: [meta-repo-template]
depended-on-by: []
pair: null
updated: 2026-06-09
---

## Назначение
Публичный шаблон для создания новых Kotlin/JVM репозиториев (Gradle).

## Ответственность / границы
**Входит:** generic Kotlin-репо (Gradle wrapper + `gradle/libs.versions.toml`, ktlint, CI/CodeQL/release
через Maven Central, community-health, агентские доки). Доп. токены `__PackageName__` (dotted package
+ src-dir) и `__Group__` (Maven group); init двигает token-package dir. **НЕ входит:** наши процессы.

## Публичный интерфейс / точки входа
`scripts/init.{ps1,sh}`, release `workflow_dispatch` (Gradle publish, `publishToMavenLocal`-валидация).
CI использует `shell: bash` (нужно `./gradlew` на Windows).

## Сборка и тесты (в сгенерированном репо)
`./gradlew build` / `./gradlew test`.

## Связи
Создаётся из `meta-repo-template`. Паритет стандартов: cs/fs/rs.

## ПРАВИЛО публичности
Shipped-файлы generic. `.hq`-интеграция — только в `CLAUDE.local.md` (git-ignored). См. `../../knowledge/templates.md`.

## Ссылки
`../../../.Templates/kotlin-repo-template/`, `../../../.Templates/TEMPLATE-STANDARDS.md`
