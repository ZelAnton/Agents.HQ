---
id: TASK-0015
type: task
title: Оркестратор P4 — jj-интеграция + авто-land низкого риска
date: 2026-06-09
scope: orchestrator
status: done
priority: P2
repos: [orchestrator]
depends-on: [TASK-0014]
parallel-safe-with: []
assigned-to: null
origin: orchestrator/ROADMAP.md (P4)
---

## Цель
Автоматическое слияние и приземление безопасного; рисковое — человеку.

## Детали
План: [`../ROADMAP.md`](../ROADMAP.md) (P4) + [`../IMPLEMENTATION.md`](../IMPLEMENTATION.md) (§4 интеграция/конфликты, §7 риски).

## Объём / что делаем
- `Merge`-агент (`agents/hq-merge.md`) + инкрементальный `jj rebase` на интеграционную ревизию (конфликты не блокируют).
- `Verifier`-агент (`agents/hq-verify.md`, переиспользует `code-review`/`security-review`) как гейт против DoD.
- **Диск автономии**: `auto-low` → авто-land после зелёного гейта; иначе `DEC` человеку (через `vcs-toolkit`).

## DoD
- [x] `risk()` определён исполнимо и **fail-closed** (`IMPLEMENTATION.md §11.1`) в `bin/land.ps1`: low ⇔ build∧tests зелёные (skipped⇒не-зелёный) ∧ Verifier=pass ∧ dod_met ∧ out_of_scope пуст ∧ нет конфликтов ∧ conflicts_resolved пуст ∧ нет чувствительных путей ∧ размер ≤ порога ∧ нет утечек ∧ autonomy=auto-low. Любое сомнение/ошибка ⇒ not-low ⇒ DEC. Непустые конфликты ⇒ не-low (§11.2).
- [x] Гейт «нет нерешённых jj-конфликтов» перед land (`jj log -r '<change> & conflicts()'` пусто, §11.3); авторитетный перезапуск `cargo build`+`cargo test` в ws перед auto-land; `skipped` = НЕ-зелёный.
- [x] Кросс-репо порядок (§11.4) — продуктовые репо защищены дефолтом `autonomy: propose` (нет карточки/поля ⇒ propose ⇒ никогда не auto-land). Правило «фундамент не land при незавершённых downstream» зафиксировано (актуально с P5/мульти-задачного тика).
- [x] Контур DEC замкнут (§11.7): `land.ps1` заводит `human/decisions/DEC-####` (+строка в `INBOX.md`); `-Resume <DEC>` читает ответ человека (`answer.decision`+`status:answered`), исполняет `A=land`/`B=abandon`, ставит `consumed-at` (идемпотентно — повтор отклоняется).
- [x] Низкорисковое авто-приземлено (Case-1: тесты+Verifier зелёные → `jj bookmark move main` + `jj git push` → проверено на bare-remote); рисковое корректно эскалировано (Case-2 чувствительный `Cargo.toml`→DEC; Case-3 сломанный build→DEC); откат на провале — `-Resume B` (forget ws + rm dest).

## Реализация
`agents/hq-verify.md` + `schemas/verify.schema.json` (Верификатор: состязательное ревью diff против DoD,
`{verdict,dod_met,findings,out_of_scope}`) + `bin/land.ps1` (интеграция `jj git fetch`+rebase-при-сдвиге →
гейт конфликтов §11.3 → авторитетный build/test → Верификатор → `risk()` fail-closed → auto-land **или** DEC;
`-Resume`, `-Autonomy`-оверрайд, autonomy из `card.md`) + `bin/make-scratch-repo.ps1` (безопасный полигон:
`cargo init --lib` + `.gitignore` + `jj git init` + локальный bare-remote + начальный push) +
фикстуры `_fixtures/sample-scratch-{low,sensitive}.md`. Мелкий фикс `exec-one.ps1`: `-RunDir`→absolute
(иначе ломается после `Push-Location $dest`).

**Валидация (реальный прогон 2026-06-10, scratch jj-репо + локальный bare-remote, продуктовые репо не тронуты):**
- **Case-1 (low→auto-land):** Verifier=pass, risk=low → main сдвинут + push; изменение подтверждено на bare-remote.
- **Case-2 (чувствительное):** diff трогает `Cargo.toml` → risk=not-low → DEC-0001, main не сдвинут. `-Resume A` (человек) → land+push.
- **Case-3 (сломанный build):** авторитетный гейт build/test=fail → risk=not-low → DEC-0002, main не сдвинут. `-Resume B` → abandon (ws forgotten, dest removed).
- Идемпотентность DEC (повторный `-Resume` отклонён по `consumed-at`); Верификатор реально поймал дефекты (несоответствие `rust-version`, синтаксическую ошибку).

**Отклонения (зафиксировано):** `hq-merge.md` (авто-разрешение конфликтов) НЕ в P4 — конфликты ⇒ DEC (§11.2);
авто-merge и внутри-репо параллель — P5. `vcs-toolkit` для DEC не задействован (DEC ведётся файлами `human/`);
адопция — позже. Валидация auto-land — на scratch-полигоне; включение `auto-low` на реальных репо — отдельное решение.

## Зависимости
Только-после P3.
