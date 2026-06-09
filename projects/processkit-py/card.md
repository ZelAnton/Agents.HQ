---
repo: processkit-py
type: card
kind: library
language: Rust+PyO3 (Python bindings)
status: no-repo-yet
publishes: ["PyPI: processkit (план)"]
depends-on: [ProcessKit-rs]
depended-on-by: []
pair: null
updated: 2026-06-09
---

## Назначение
**(Репозитория ещё нет — планируется.)** Тонкие Python-биндинги к ядру `processkit` (Rust),
**не** реимплементация. Ядро остаётся единственным источником истины; биндинг тонкий (PyO3 + maturin,
`pyo3-async-runtimes` для tokio↔asyncio, abi3-колёса через cibuildwheel). Имя на PyPI — `processkit`,
репозиторий — `processkit-py` (рядом с `ProcessKit-rs`).

## Ответственность / границы
**Входит (будет):** asyncio-поверхность, контекст-менеджеры teardown, маппинг ошибок в Python-исключения.
**НЕ входит:** логика ядра/per-platform код → `ProcessKit-rs`.

## Публичный интерфейс / точки входа
План: `Command`, `ProcessGroup` (context manager), `output()`/`run()`/`start()`, async-стриминг.

## Сборка и тесты
```
(maturin build / cibuildwheel — когда заведётся репо)
```

## Связи и зависимости
Биндинг к `ProcessKit-rs`; пиннит точную версию crate, churn API отслеживается осознанно.

## На что смотреть при кросс-репо изменениях
Следует за версией `processkit`. Windows `KILL_ON_JOB_CLOSE` так же надёжен; Linux teardown —
best-effort (нет детерминированного `Drop` в Python). Roadmap и фазы — см. ниже.

## Ссылки
- Roadmap (мигрирован): `./ROADMAP.md` (и `knowledge/`-заметки в этом проекте)
- Источник истины: `../ProcessKit-rs/card.md`
