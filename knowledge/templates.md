---
type: knowledge
topic: repo-templates
updated: 2026-06-09
---

# Шаблоны репозиториев (`d:\GitHub\Personal\.Templates`)

Набор **публичных** шаблонов для создания новых репозиториев на разных языках. Из них
репозитории создают и я, и **другие люди** — у которых могут быть **иные процессы**, чем
наш локальный `.hq`. Поэтому действует жёсткое правило публичности (ниже).

## Шаблоны (8, все jj-colocated git-репо)

| Шаблон | Язык | Реестр публикации | Примечание |
|---|---|---|---|
| `cSharp-repo-template` | C#/.NET | NuGet.org | source-of-truth для многих стандартов |
| `fSharp-repo-template` | F#/.NET | NuGet.org | без CodeQL (нет F#-экстрактора) |
| `kotlin-repo-template` | Kotlin/JVM | Maven Central (Gradle) | доп. токены `__PackageName__`/`__Group__` |
| `rust-repo-template` | Rust | crates.io | без CodeQL; toolchain-ref не пиннится |
| `Go-repo-template` | Go | Go module / pkg.go.dev | — |
| `Python-repo-template` | Python | PyPI | — |
| `ts-repo-template` | TypeScript | npm | — |
| `meta-repo-template` | (мета) | — | **шаблон для создания `<lang>-repo-template`**; `%%`-мета-токены; см. `META-AUTHORING.md` |

Общая структура (по `TEMPLATE-STANDARDS.md`): токены `__ProjectName__`/`__Author__`/…,
дуальные `scripts/init.{ps1,sh}`, CI (pinned actions, OS-matrix, yamllint, dependabot),
release-workflow (`workflow_dispatch` + bump + GitHub App bypass, см. `release-token-bypass.md`),
community-health (`SECURITY.md`/`CONTRIBUTING.md`/`PULL_REQUEST_TEMPLATE.md`/`CODEOWNERS`),
и **generic** агентские доки (`AGENTS.md` = полный справочник, `CLAUDE.md` = primer).

## ПРАВИЛО публичности (критично)

> **Отслеживаемые (shipped) файлы шаблона остаются generic — никаких упоминаний `.hq`,
> наших локальных процессов или личных данных.** Они копируются в новые репозитории, в т.ч.
> у других людей.
>
> **`.hq`-интеграция шаблона — только локально**, в git-ignored файле (`CLAUDE.local.md`,
> заигнорен через `.git/info/exclude`), который не коммитится и не пушится. См. этот файл
> в каждом шаблоне.

В самих шаблонах `AGENTS.md`/`CLAUDE.md`/`.claude/` **остаются tracked** (так шиппится guidance) —
это by design, не трогаем. Рецепт «сделать агентские доки локальными» относится к
**сгенерированным** репо и уже описан generic-образом в шаблонном `AGENTS.md`.

## Связи
- `meta-repo-template` — источник для `<lang>-repo-template` (мета-шаблон).
- `TEMPLATE-STANDARDS.md` (в `.Templates/`) — канон общих стандартов. **Stale:** перечисляет
  4 шаблона (cs/fs/kt/rs), а сейчас их 8 (добавлены Go, Python, ts, meta) — кандидат на
  обновление (кросс-шаблонная задача в `../tasks/`).

Карточки: `../projects/<template>/card.md`.
