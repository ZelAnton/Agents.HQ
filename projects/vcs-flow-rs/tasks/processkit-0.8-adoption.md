# processkit 0.6 → 0.8.2 — инструкция для агентов, работающих над `vcs-flow-rs`

> Аудитория: кодинг-агент, разрабатывающий `d:\GitHub\Personal\vcs-flow-rs`
> (TUI `commit`: stage-free коммиты, AI-черновики через `copilot`, git/jj через
> vcs-core, PR через gh). **processkit 0.8.2 опубликован на crates.io** —
> переходим с 0.6 сразу на 0.8 (0.7 пропускаем; 0.6.2 была отравлена и yank-нута
> давно — если в `Cargo.lock` каким-то чудом 0.6.2, `cargo update -p processkit`
> снимет её при переходе на 0.8). Флор `"0.8"` резолвится в ≥0.8.2 (0.8.1 — фикс
> crates.io-обложки, 0.8.2 — batch-фан-аут, не профиль TUI; см. §3).
> Справка: docs.rs/processkit; cookbook —
> https://github.com/ZelAnton/ProcessKit-rs/blob/main/docs/cookbook.md
> (там есть рецепты под cancellation, scripted streaming, тестирование).

## 0. Критично: порядок апгрейда

НЕ поднимать processkit до 0.8 в этом репо, пока `vcs-toolkit-rs` не выпустил
vcs-core/vcs-git/vcs-jj/vcs-github, собранные против processkit **0.8**. Caret
`"0.6"` не захватывает 0.8 → прямой processkit@0.8 + vcs-*@(processkit 0.6/0.7)
дадут ДВА processkit в графе, и `ProcessResult`, который возвращают typed-вью
(`repo.git_at()`), перестанет совпадать по типу с тем, что ждёт наш код в
`vcs.rs`. Апгрейд — одним коммитом: `processkit = "0.8"` + новые версии всех
vcs-*. Признак беды: `cargo tree -d` показывает processkit дважды.

## 1. Миграция: что может затронуть `commit` (кумулятивно за 0.6→0.8)

Используются default features → breaking-часть (фичи `stats`/`process-control`
default-on; изменившийся смысл `default-features = false`) нас не касается.
Точки внимания:

- **`Command` теперь `#[must_use]`** (с 0.7) — Command, собранный и не доведённый
  до глагола (`output_string()` и т.п.), станет warning'ом. В `ai.rs`/`vcs.rs`
  команды строятся и сразу исполняются — ок; проверит clippy.
- **`Error` `#[non_exhaustive]` + новые варианты** (с 0.7): `Cancelled`,
  `NotReady`, `ResourceLimit`, `Unsupported`. Наш код матчит результат методами
  (`is_success`/`timed_out`/`diagnostic`), не вариантами — влияния нет. Если
  появится матч по вариантам — всегда с catch-all.
- **`Error::Exit` Display стал длиннее** (0.8): в одну строку добавляется хвост
  диагностики (`` `git` exited with code 2: fatal: boom ``). Текст не входит в
  semver-контракт; поля и `diagnostic()` не менялись. Если есть тест на
  **точный** текст `Error::Exit` через `to_string()` — обновить.
- **`CliClient` вербы переименованы** (0.8): `text/capture/unit/code →
  run/output/run_unit/exit_code`. Нас задевает, **только если** мы где-то зовём
  `CliClient`-вербы напрямую (мы строим `Command` сами, так что почти везде N/A) —
  но если в §2.2 берём runner-шов, используем новые имена (`r.output(&cmd)`, не
  `r.capture`).
- Поведенческие фиксы прозрачны; один прямо про нас (с 0.7): **`output_bytes`/
  drain больше не зависает**, когда дескендант держит pipe — TUI это страховка
  от «подвисшего» шага. Плюс 0.8: **паника пользовательского `on_*_line`-хэндлера
  больше не валит прогон** (если когда-нибудь повесим прогресс-хэндлер на
  copilot/git).

## 2. Новое, что стоит ВЗЯТЬ (по убыванию ценности для commit-TUI)

### 2.1 `cancellation` — главная фича для TUI (Esc обрывает прогон)

Сейчас copilot ограничен `timeout(45s)`, и пользовательский Esc не может
оборвать уже запущенный прогон — future просто бросается. С 0.8:

```toml
processkit = { version = "0.8", features = ["cancellation"] }
```

```rust
use processkit::CancellationToken;

let token = CancellationToken::new();           // живёт в состоянии TUI
let draft = Command::new("copilot")
    .args([...])
    .timeout(Duration::from_secs(45))           // потолок остаётся
    .cancel_on(token.child_token())
    .output_string();                            // future
// в обработчике Esc: token.cancel();
```

Семантика, на которую можно опереться:
- Отмена **убивает всё дерево** copilot'а (private group) и **всегда** даёт
  `Err(Error::Cancelled)` — в отличие от timeout, который у `output_string`
  *захватывается* в результат (`timed_out()`), как мы уже обрабатываем.
- Одновременные cancel+timeout → побеждает cancel. Уже отменённый токен
  коротит ДО спавна — дешёвый guard при выходе из экрана.
- На наш re-prompt-цикл «модель недоступна» не влияет: отмена терминальна,
  ретраить отменённый прогон не нужно (и retry processkit'а её не ретраит).

Тот же токен уместен на git-plumbing батче (`plumb*`-хелперы), если шаг
конструирования коммита захочется сделать прерываемым.

### 2.2 НОВОЕ в 0.8: герметичный тест Esc-отмены — `Reply::pending()`

Раньше отмену нельзя было протестировать без реального бинаря (можно было
заскриптить только *последствие* — canned `Error::Cancelled`). 0.8 даёт
`Reply::pending()` (фича `cancellation`): `ScriptedRunner` паркует вызов, пока
токен команды не сработает, затем `Err(Error::Cancelled)`:

```rust
// тест: «Esc реально обрывает черновик и экран чистится»
async fn draft_message<R: processkit::ProcessRunner>(r: &R, ...) -> Result<String> {
    let cmd = Command::new("copilot").args([...]).cancel_on(token.child_token());
    Ok(r.output(&cmd).await?.into_stdout())     // ProcessRunnerExt::output
}

#[tokio::test(start_paused = true)]
async fn esc_cancels_the_draft() {
    let token = CancellationToken::new();
    let r = ScriptedRunner::new().on(["chat"], Reply::pending());
    let call = draft_message(&r, /* token живёт в состоянии */);
    tokio::pin!(call);
    // ... вызов не резолвится ...
    token.cancel();                              // имитируем Esc
    assert!(matches!(call.await, Err(/* Cancelled */)));
}
```

Это закрывает дыру: теперь cancellable-путь (реально ли отменяется? чистится
ли стейт?) тестируется без copilot-бинаря.

### 2.3 Тестируемость AI-шага: runner-шов + `record`-кассеты

Сейчас `ai.rs` зовёт `Command::output_string()` напрямую — юнит-тестов на
разбор ответа copilot без реального бинаря не сделать. Рекомендуемый паттерн
(минимальный диф) — generic по runner'у (тот же, что в §2.2):

```rust
// было: свободная функция, внутри Command::new("copilot")...
// стало: generic по runner'у
async fn draft_message<R: processkit::ProcessRunner>(r: &R, ...) -> Result<String> {
    let cmd = Command::new("copilot").args([...]).timeout(...);
    let result = r.output(&cmd).await?;   // ProcessRunnerExt::output (был `capture` до 0.8)
    ...
}
```

В проде — `JobRunner::new()` (то же поведение), в тестах — `ScriptedRunner`
(`Reply::ok(...)` / `Reply::fail(...)` / `Reply::timeout()` / `Reply::pending()`),
а для интеграционных фикстур — `record`-фича: `RecordReplayRunner::record(...)`
пишет реальные `copilot`-ответы в JSON-кассету (env-значения в файл не
попадают — токены не утекут), `::replay(...)` гоняет их в CI без сабпроцесса.
Матчинг кассеты: program+args+cwd+has-stdin → для copilot без `current_dir`
кассеты стабильны. (Кассеты пишут только bulk-`output`; стриминг — §2.4.)

### 2.4 НОВОЕ в 0.8: если copilot стримит прогресс — герметичный стрим-тест

Если черновик читается построчно (прогресс модели), 0.8 делает это
тестируемым: `ScriptedRunner::start` отдаёт scripted-`RunningProcess`, чьи
canned-строки идут через ту же pump-машинерию — `stdout_lines`/`wait_for_line`
работают без сабпроцесса:

```rust
let r = ScriptedRunner::new()
    .on(["chat"], Reply::lines(["thinking…", "done"]).with_line_delay(d)); // paced
let mut run = r.start(&Command::new("copilot").args([...])).await?;
let mut lines = run.stdout_lines();
while let Some(l) = lines.next().await { /* обновить TUI */ }
```

Также bulk-вербы (`output`) теперь проигрывают canned-вывод через
`on_stdout_line`/`on_stderr_line` — если вешаем прогресс-хэндлер, он
тестируется герметично. Паника хэндлера больше не валит прогон (0.8).

### 2.5 `ProcessResult::program()`, `diagnostic()`, `outcome()`

- `diagnostic()` мы уже используем; `program()` дополняет его для сообщений об
  ошибке шага, когда один код гоняет и `git`, и `copilot`:
  `format!("{} failed: {}", res.program(), res.diagnostic().unwrap_or("(no output)"))`.
- НОВОЕ в 0.8: `outcome()` — явный `Outcome::{Exited(i32), Signalled, TimedOut}`
  вместо дешифровки пары `code()/timed_out()`. Аксессоры не менялись (миграция
  не нужна); берите, если различаете «timeout vs ненулевой код» в сообщениях.

### 2.6 `Stdin::from_string` для plumbing

`git hash-object --stdin` / `update-index --index-info`-подобные шаги, если
появятся, кормить через `Stdin::from_string(payload)` вместо временных файлов.
Помнить: `from_reader`/`from_lines` — одноразовые источники; при `retry`
второй заход получит пустой stdin (наш plumbing не ретраится — ок).

## 3. Что осталось КАК ЕСТЬ (осознанные решения — не «чинить»)

- **`gh --web` через `std::process` — оставить.** 0.8 не меняет расклад:
  processkit-спавн кладёт `gh` в kill-on-drop контейнер, и на Windows Job
  Object порождённый браузер умер бы вместе с группой. Детач-браузер — не
  сценарий processkit. Комментарий в коде об этом сохранить.
- 45-секундный timeout + проверка `timed_out()` — корректный идиоматичный
  паттерн, менять не нужно (cancel — дополнение, не замена).
- `limits`/`Supervisor` (вкл. storm-guard)/readiness-пробы/`members` — не
  профиль TUI-однострелов.
- **batch-фан-аут** (`output_all`/`wait_all`, новое в 0.8.2) — ограниченный по
  конкурентности запуск МНОГИХ команд разом (лимит параллелизма, защита от
  исчерпания fd, collect-all исходов). Commit-flow строго последовательный
  (git-статус → черновик copilot → git-коммит → gh-PR), массового параллелизма
  нет → не наш профиль. Знать на случай, если появится «прогнать по N репо».

## 4. Чек-лист апгрейда

1. Дождаться релиза vcs-* под processkit **0.8** (см.
   `processkit-0.8-instructions-vcs-toolkit-rs.md`).
2. Одним изменением: `processkit = "0.8"` (+ `features = ["cancellation"]`,
   если берём отмену сразу) и бамп vcs-core/vcs-git/vcs-jj/vcs-github.
3. `cargo update`; в `Cargo.lock` — ровно один processkit.
4. clippy `-D warnings` (must_use из 0.7); тесты, ручной прогон TUI:
   copilot-черновик, Esc во время черновика (если cancel взят), plumbing-коммит,
   gh-PR с `--web`. Если взяли §2.2 — герметичный тест Esc-отмены.
5. MSRV: processkit 0.8 держит 1.88 — наш комментарий в Cargo.toml про
   rust-version остаётся верным.
