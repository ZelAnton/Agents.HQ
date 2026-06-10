---
repo: <name>
type: card
kind: library           # library | cli | tui | tooling | marketplace
language: Rust          # Rust | C#/.NET | mixed | ...
status: active          # active | maintenance | experimental | no-repo-yet
autonomy: propose       # оркестр: propose | assist | auto-low (отсутствует ⇒ propose)
shared_files: []        # P5: общие/моноширинные файлы репо (любая задача, трогающая их, авто-сериализуется; §11.6). Cargo.toml/lib.rs/mod.rs и т.п. учитываются и по умолчанию.
publishes: []           # crates.io: ... / NuGet: ... / PyPI: ... / нет
depends-on: []          # репо из этого пространства
depended-on-by: []
pair: null              # -rs/.NET двойник или null
updated: YYYY-MM-DD
---

## Назначение
<!-- Одно-два предложения: что делает репо. -->

## Ответственность / границы
<!-- Что ВХОДИТ в зону репо и чего касаться НЕ нужно (чтобы агенты не лезли в чужое). -->

## Публичный интерфейс / точки входа
<!-- Что другие репо/агенты используют: crate API, CLI-команды, типы. -->

## Сборка и тесты
```
<команды>
```

## Связи и зависимости
<!-- На кого опирается, кто опирается на него; пара -rs/.NET. -->

## На что смотреть при кросс-репо изменениях
<!-- Что сломается у потребителей, паритет пары, порядок сборки. -->

## Ссылки
<!-- Tracked-доки в самом репо: ../<repo>/ROADMAP.md, ../<repo>/docs/*, README. -->
