# processkit 0.6 → 0.8.2 — инструкция для агентов, работающих над `agent-workspace`

> Аудитория: кодинг-агент, разрабатывающий `d:\GitHub\Personal\agent-workspace`
> (бинарь `ws`: мгновенные git/jj worktree'ы для параллельных AI-агентов,
> snap-режим, CoW-клоны, hooks). **processkit 0.8.2 опубликован на crates.io** —
> переходим с 0.6 сразу на 0.8 (0.7 пропускаем; 0.6.2 была отравлена и yank-нута
> давно — `cargo update -p processkit` снимет её при переходе на 0.8, если
> вдруг залочена). Флор `"0.8"` резолвится в ≥0.8.2 (0.8.1 — фикс
> crates.io-обложки, без API; 0.8.2 добавил batch-фан-аут — §2.7, прямо в тему
> мультиворктри `ws`).
> Справка: docs.rs/processkit; cookbook —
> https://github.com/ZelAnton/ProcessKit-rs/blob/main/docs/cookbook.md.

## 0. Критично: порядок апгрейда

`ws` зовёт processkit ДВУМЯ путями: напрямую (`git_cmd`/`jj_cmd` в `src/vcs/`)
и через typed-клиенты `vcs-git`/`vcs-jj` (которые ре-экспортируют
`processkit::Error`). Caret `"0.6"` не захватывает 0.8 → поднимать прямую
зависимость можно ТОЛЬКО одновременно с версиями vcs-*, собранными против **0.8**
(их выпускает vcs-toolkit-rs — см. соседнюю инструкцию). Иначе в графе будут
два processkit, и наш `src/vcs/error.rs::map_pk_err` перестанет принимать
ошибки от typed-клиентов (другой тип с тем же именем). Признак беды:
`cargo tree -d` показывает processkit дважды.

## 1. Миграция: что может затронуть `ws` (кумулятивно за 0.6→0.8)

Default features → breaking-часть (`stats`/`process-control` default-on,
изменившийся смысл `default-features = false`) не задевает. Точки внимания:

- **`Error` `#[non_exhaustive]`, новые варианты** (с 0.7): `Cancelled`,
  `NotReady`, `ResourceLimit`, `Unsupported`. Наши матчи (`error.rs`,
  `git/repo.rs`, `jj/repo.rs`, `git/worktree.rs`) все с catch-all —
  компилируются и ведут себя корректно. НЕ делать их исчерпывающими; новые
  варианты должны падать в default-ветку `map_pk_err`.
- **`Command` `#[must_use]`** (с 0.7) — `git_cmd`/`jj_cmd` возвращают Command,
  который сразу исполняется; warning возможен только в новом коде, бросающем
  Command.
- **`Error::Exit` Display стал длиннее** (0.8): добавляет хвост диагностики.
  `map_pk_err` матчит по **варианту/полям**, не по тексту Display — влияния нет;
  но если где-то логируем `Error::Exit.to_string()` в snap-протокол, текст
  изменится (не ломает контракт, текст не semver).
- **`CliClient` вербы переименованы** (0.8, `text/capture/unit/code →
  run/output/run_unit/exit_code`) — `ws` строит `Command` напрямую и ходит через
  typed-клиенты, `CliClient`-вербы не зовёт → **N/A для нашего кода**.
- Фикс (с 0.7), который нас реально касается: **POSIX `adopt` больше не silent
  no-op** для exec'нутых детей, probe-логика различает EPERM/ESRCH — если берём
  ProcessGroup (§2.1), он уже починен под наш кейс.

## 2. Новое, что стоит ВЗЯТЬ (по убыванию ценности для `ws`)

### 2.1 `ProcessGroup` для hooks — закрыть «hooks run unsandboxed»

Сегодня репо/worktree-хуки запускаются без контейнера: повисший или форкающий
хук переживает `ws` и держит файлы worktree (ломая cleanup на Windows). 0.8
делает контейнер дешёвым и управляемым:

```rust
use processkit::{ProcessGroup, Command};

let group = ProcessGroup::new()?;                       // kill-on-drop
let hook = group.start(&Command::new(hook_cmd)
        .current_dir(worktree)
        .timeout(hook_timeout))                          // дедлайн на хук
    .await?;
let result = hook.output_string().await?;                // timed_out() в результате
// drop(group) гарантированно реапит ВСЁ дерево хука (Job/cgroup/pgroup),
// или мягко: group.shutdown().await?  — TERM → grace → KILL (Unix),
// настраивается ProcessGroupOptions { shutdown_timeout, escalate_to_kill, .. }.
```

Опционально для недоверенных хуков — фича `limits` (off-default; Windows
Job / Linux cgroup): `ProcessGroupOptions::default().memory_max(..)
.max_processes(..).cpu_quota(..)`; там, где контейнера нет (macOS, pgroup-
fallback), `with_options` честно вернёт `Error::ResourceLimit`, а не тихо
небезлимитную группу — обработать как «лимиты недоступны, запускаем без них»
(пере-вызов `ProcessGroup::new()`), это осознанный паттерн.

То же применимо к snap-режиму, если когда-нибудь `ws` будет сам спавнить
агентский процесс (сейчас агент живёт в родительском шелле — там это не наш
процесс; не трогать).

### 2.2 НОВОЕ в 0.8: `kill_on_parent_death()` — хук не переживёт даже SIGKILL `ws`

§2.1 (kill-on-drop) убивает дерево хука при **штатном** выходе `ws` (Drop
бежит). Но если `ws` убьют **резко** (SIGKILL, паника без unwind, kill из
менеджера задач) — Drop НЕ бежит, и хук на Linux может пережить `ws` и держать
файлы worktree (исходный краш-кейс блокировки на Windows). 0.8 закрывает и это:

```rust
let hook = group.start(&Command::new(hook_cmd)
        .current_dir(worktree)
        .timeout(hook_timeout)
        .kill_on_parent_death())                         // ← опт-ин hardening
    .await?;
```

- **Windows** — гарантировано и так (Job kill-on-close: ядро закрывает хэндл
  при смерти `ws`); этот флаг там no-op.
- **Linux** — армит `PR_SET_PDEATHSIG(SIGKILL)` на **прямого** ребёнка хука
  (контейнер-PID-1-safe: сверяется с pid спавнера, а не с литералом 1). Внуки
  хука не покрыты — их добивает cgroup/pgroup при штатном Drop, но при SIGKILL
  `ws` гарантия — только прямой ребёнок.
- **macOS/BSD** — нет аналога, документированный no-op (kill-on-drop при
  штатном выходе остаётся).

Прямой ответ на нашу цель «хук не должен пережить `ws` и залочить worktree».
Брать на спавне хуков вместе с §2.1.

### 2.3 `cancellation` — Ctrl-C на долгих VCS-операциях

Долгие `git fetch`/merge/CoW-подготовка под Ctrl-C сейчас обрываются дропом
future. Токен делает это детерминированным и наблюдаемым:

```toml
processkit = { version = "0.8", features = ["cancellation"] }
```

```rust
let cmd = git_cmd(cwd, ["fetch", "--all"]).cancel_on(shutdown_token.child_token());
```

`Err(Error::Cancelled)` всегда (побеждает timeout); в `map_pk_err` он попадёт
в default-ветку — при желании добавить отдельное сообщение «operation
cancelled», но это не обязательно для корректности. Отменённый прогон не
ретраится typed-клиентами (их fetch-retry считает cancel терминальным).

### 2.4 `ProcessResult::program()` и `outcome()`

- `program()` — в `exec`/`capture`-хелперах, общих для git и jj, готовое имя
  программы для сообщений: `res.program()` вместо протаскивания строки рядом с
  результатом.
- НОВОЕ в 0.8: `outcome()` — явный `Outcome::{Exited(i32), Signalled, TimedOut}`.
  В `map_pk_err`/классификации удобнее, чем дешифровка `code()/timed_out()`:
  `match res.outcome() { Outcome::TimedOut => …, Outcome::Signalled => …,
  Outcome::Exited(c) => … }`. Аксессоры не менялись — миграция не нужна,
  `Outcome` — `#[non_exhaustive]`, держать catch-all.

### 2.5 Readiness-пробы — если появятся фоновые процессы

`wait_for_line(pred, within)` / `wait_for_port(addr, within)` /
`wait_for(check, within)` на `RunningProcess` — замена `sleep` при запуске
чего-либо долгоживущего из `ws` (dev-сервер в worktree по хуку и т.п.).
Провал — типизированный `Error::NotReady`, ребёнка пробы НЕ убивают.
Для текущего one-shot профиля `ws` — на полку, но знать.

### 2.6 Кассеты (`record`) для vcs-тестов — опционально, скорее «не брать»

Наша стратегия «тесты против реального git/jj» остаётся основной (она ловит
реальные регрессии бинарей). Кассеты (`RecordReplayRunner`) могут ускорить
CI-подмножество, НО ключ матчинга включает **cwd**, а наши тесты живут во
временных репо с уникальными путями → кассеты не сматчатся. Брать только если
появятся команды со стабильным cwd. Иначе — не тратить время. (Кассеты пишут
только bulk-`output`; стриминг ими пока не покрыт.)

### 2.7 НОВОЕ в 0.8.2: ограниченный фан-аут — `output_all` / `wait_all`

`ws` по своей природе оперирует МНОЖЕСТВОМ worktree'ов (параллельные агенты).
Везде, где сейчас запускается одна и та же операция по нескольким worktree'ам
(хук по N веткам, прогрев/CoW-подготовка пачки, проверка чистоты набора репо),
два core-примитива (без фич) заменяют наивный `futures::join_all`, который
плодит процессы без тормозов:

- `output_all(commands, concurrency, &group) -> Vec<Result<ProcessResult<String>>>` —
  запускает батч, держа живыми **не более `concurrency`** разом (защита от
  исчерпания fd/таблицы pid при десятках worktree'ов), все дети — в **одной**
  kill-on-drop группе (передайте `&ProcessGroup` из §2.1), собирает **ВСЕ**
  исходы (ненулевой выход — это `Ok(ProcessResult)` с кодом, не короткое
  замыкание; перебираете и решаете сами). Идеально под «прогнать хук по N
  worktree'ам с лимитом параллелизма и гарантированным teardown всего дерева».
- `wait_all(&mut [&mut RunningProcess]) -> Result<Vec<Option<i32>>>` — джойн уже
  запущенных хендлов, коды в порядке входа (компаньон `wait_any`).

`output_all` **не** cancel-safe (владеет порождёнными детьми — дроп future рвёт
незавершённые деревья); нужен прерываемый батч — комбинируйте с §2.3 (токен на
каждой команде). Это не пул/шедулер/ретраер.

## 3. Что НЕ трогать

- Тонкие места snap-протокола (exit-коды 0/2/3) и shell-wrapper — processkit
  тут ни при чём.
- Не вводить `default-features = false` «для лёгкости»: это прячет ещё и
  tree-control поверхность; выигрыша в зависимостях нет (tokio уже тянет
  libc/windows-sys) — это задокументированный вывод самого processkit.
- Не конструировать `ProcessGroupStats`/`RunProfile`/`SupervisionOutcome`
  литералами (все `#[non_exhaustive]`) — только читать поля.

## 4. Чек-лист апгрейда

1. Дождаться vcs-git/vcs-jj (и транзитивно vcs-core), собранных под
   processkit **0.8** (см. `processkit-0.8-instructions-vcs-toolkit-rs.md`).
2. Одним изменением поднять: `processkit = "0.8"` + vcs-git/vcs-jj (и их
   `mock`-фичи в dev-deps).
3. `cargo tree -d` — processkit в графе ровно один; `windows-sys` тоже один.
4. clippy `-D warnings`; тесты: юнит (парсеры), интеграционные с реальными
   git/jj на временных репо, ручной smoke snap-режима на Windows
   (worktree cleanup — место, где контейнеризация хуков из §2.1+§2.2 проявится).
5. Если взяли §2.1/§2.2: добавить тест «хук, который форкает sleep и выходит» —
   убедиться, что после `ws` cleanup дерево хука мертво и worktree удаляется
   (на Windows это и был исходный краш-кейс блокировки файлов); по возможности
   проверить и резкий путь (SIGKILL `ws` на Linux → прямой ребёнок хука мёртв).
