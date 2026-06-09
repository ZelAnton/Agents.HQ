# processkit 0.7.1 → 0.8.2 — инструкция для агентов, работающих над `vcs-toolkit-rs`

> Аудитория: кодинг-агент, разрабатывающий `d:\GitHub\Personal\vcs-toolkit-rs`
> (vcs-git / vcs-jj / vcs-github / vcs-core / vcs-cli-support).
> **processkit 0.8.2 опубликован на crates.io** — последний патч 0.8.x; флор
> `"0.8"` резолвится в ≥0.8.2. (0.8.1 — фикс crates.io-обложки, без API; 0.8.2
> добавил batch-фан-аут — §2.9.) Справка: docs.rs/processkit, гайды в `docs/`
> репозитория (testing.md и cookbook.md заметно расширены — там есть готовые
> рецепты под всё нижеперечисленное).

---

## 0. Порядок апгрейда экосистемы — тот же закон, что и в 0.7

`vcs-toolkit-rs` — **первый** в цепочке: vcs-* ре-экспортируют
`processkit::Error` / `ProcessResult`, поэтому бамп processkit делает их релиз
breaking. Caret `"0.7"` **не** захватывает 0.8 → если поднять прямой processkit
до 0.8, а vcs-* оставить на 0.7, в графе окажутся два processkit и типы
перестанут совпадать. Поэтому:

1. Здесь: `[workspace.dependencies] processkit = "0.8"` (+ нужные фичи).
2. Прогнать матрицу, выпустить новые версии vcs-* (мажор/минор — ре-экспорт
   типов делает это breaking для них).
3. Только потом консьюмеры (vcs-flow-rs, agent-workspace) поднимают
   processkit + vcs-* одним коммитом.

MSRV не менялся (1.88). Кассеты, записанные на 0.7, **совместимы** —
wire-формат не трогали.

---

## 1. Миграция: что ломается (по убыванию объёма работы)

### 1.1 Verb-переименования на `CliClient` — основная механическая работа

Глаголы `CliClient` приведены к единому словарю всех трёх слоёв (`Command`,
`ProcessRunnerExt`, `CliClient`): один глагол = одно значение везде.

| Было | Стало | Семантика |
|---|---|---|
| `self.core.text(cmd)` | `self.core.run(cmd)` | trimmed stdout, ошибка на non-zero |
| `self.core.capture(cmd)` | `self.core.output(cmd)` | полный `ProcessResult`, non-zero — данные |
| `self.core.unit(cmd)` | `self.core.run_unit(cmd)` | побочный эффект, stdout отброшен, ошибка на non-zero |
| `self.core.code(cmd)` | `self.core.exit_code(cmd)` | код выхода (timeout/signal → ошибка) |
| `probe` / `parse` / `try_parse` | без изменений | — |

Deprecated-алиасов нет (pre-1.0). Это **самая объёмная** часть апгрейда, но
чисто механическая: компилятор перечислит все места.

> ⚠️ **Ловушка find-replace:** `ProcessResult::code()` (аксессор результата)
> **НЕ** переименован — это другой `code`. Голый `\.code\(` заденет и его, и
> переименовываемый `CliClient::code`. Фильтруйте по получателю: меняем только
> `self.core.code(` / `<client>.code(`, не `result.code()` /
> `stage.code` / `outcome` в классификаторах.

Ваш собственный публичный API (`Repo::head()`, `Git::is_clean()`, …) **не
каскадирует** — правки только в телах обёрток, которые зовут `self.core.*`.
Значит, vcs-flow-rs / agent-workspace от этого переименования не страдают
(в отличие от ре-экспорта типов).

`ProcessRunnerExt` получил новый `run_unit` для полной симметрии — если
где-то звали `runner.checked(...).map(drop)`, замените на `run_unit`.

### 1.2 `SupervisionOutcome` стал `#[non_exhaustive]`

Появилось поле `storm_pauses: u32`. Сломается только код, который конструирует
`SupervisionOutcome` литералом или матчит его исчерпывающе без `..` — у
vcs-toolkit такого быть не должно, но **проверьте** (vcs-mcp/оркестраторы).

### 1.3 `Error::Exit` Display теперь длиннее (не breaking, но заметно в логах)

`Error::Exit` в одну строку теперь добавляет хвост диагностики:
`` `git` exited with code 2: fatal: boom `` (последняя непустая строка stderr,
кап 200 байт). Текст Display не входит в semver-контракт; поля `stdout`/`stderr`
и `diagnostic()` не менялись. Если у вас есть тесты, ассертящие **точный**
текст `Error::Exit` через `to_string()` — обновите их (матчинг по варианту/
полям не задет).

---

## 2. Новое, что стоит ВЗЯТЬ (по убыванию ценности для vcs-toolkit)

### 2.1 Клиент-уровневая отмена — `CliClient::default_cancel_on` (ваша cancellation-спека закрыта)

Это прямой ответ на `processkit-client-cancellation-spec.md` (полный Response —
в §5 ниже). Фича `cancellation`.

`default_cancel_on(token)` ставит токен **один раз на клиент** — каждая команда,
которую клиент строит, его несёт. Это снимает проблему «typed-методы строят и
потребляют `Command` внутри, токен некуда протащить per-call»:

```rust
// vcs-github: один отменяемый клиент на scope, нулевой новый публичный API
let token = CancellationToken::new();
let gh = GitHub::with_runner(JobRunner::new())  // или GitHub::new()
    .default_cancel_on(token.child_token());
let forge = Forge::for_github(cwd, gh);
// контроллер зовёт token.cancel() → каждый in-flight gh-вызов ЭТОГО клиента
// умирает (kill-on-close дерево), всплывает Error::Cancelled.
tokio::spawn(watchdog(token.clone()));
forge.run_watch(run_id).await  // Err(Vcs(Cancelled)) при отмене
```

- **Прецедент: override.** Per-command `cancel_on` на построенной команде
  **заменяет** клиентский default (явное бьёт дефолт, как per-command `timeout`
  после `default_timeout`). Нужны оба источника — деривьте: `let c =
  default.child_token(); cmd.cancel_on(c.clone());` и второй источник зовёт
  `c.cancel()`.
- `cli_client!` **ре-эмитит** билдер на сгенерированных обёртках (`Git`/`GitHub`/…)
  через внутренний feature-выбираемый макрос — даунстрим-крейтам ничего писать
  не надо.
- Семантика per-command `cancel_on` не менялась: отмена всегда `Error::Cancelled`,
  бьёт одновременный timeout, убивает дерево; `retry`/`Supervisor` считают её
  терминальной (fetch-retry не долбит отменённый прогон).

**Где применить:** `run_watch()` (`gh run watch` — длинный стрим), долгие
`git fetch`/`clone`/`push` по дохлой сети. Скоупите отмену **клиентом, а не
вызовом**: клиенты дешёвые — один клиент на отменяемый scope со своим
(child-)токеном.

### 2.2 Герметичный тест отмены — `Reply::pending()` (cancellation-спека R2)

`ScriptedRunner` теперь умеет тестировать **поведение** отмены, не только её
последствие. `Reply::pending()` (фича `cancellation`) паркует вызов, пока токен
команды (per-command или клиентский default) не сработает, затем
`Err(Error::Cancelled { program })`:

```rust
let token = CancellationToken::new();
let rec = RecordingRunner::new(
    ScriptedRunner::new().on(["run", "watch"], Reply::pending()));
let gh = GitHub::with_runner(&rec).default_cancel_on(token.clone());
let call = gh.run_watch("123");           // паркуется
tokio::pin!(call);
// ... вызов не резолвится ...
token.cancel();
// call.await → Err(Cancelled), invocation записан в rec
```

Без токена pending-реплай паркуется вечно (документировано — «повисший ребёнок,
которого некому отменить»; парьте с токеном или тестовым таймаутом). Теперь
ваш cancellable-путь (реально ли отменяется? чистится ли?) тестируется без
реального бинаря.

### 2.3 Стриминговые обёртки можно благословить (streaming-спека R1-R3)

`processkit-streaming-spec.md` закрыта:

- **R1 — паника хэндлера изолирована.** Паника пользовательского
  `on_stdout_line`/`on_stderr_line` ловится, хэндлер отключается на остаток
  прогона (tracing-warn при фиче), захват **доводится до конца** — результат
  несёт все строки. Контракт «keep it panic-free or else» из доков убран:
  callback-шов теперь можно re-export'ить **своим** консьюмерам, не аудируя их
  замыкания.
- **R2 — порядок задокументирован и закреплён тестом.** FIFO внутри потока; без
  порядка между stdout/stderr (два независимых пампа); на потребляющих вербах
  **все вызовы хэндлеров happen-before резолва future** — прогресс-бар
  финализируется в момент возврата `await`. (Одно исключение: повисший pipe,
  удержанный после смерти ребёнка, обрезается по bounded-grace teardown'а.)
- **R3 — bulk-вербы проигрывают canned-вывод через хэндлеры.**
  `ScriptedRunner::output` при наличии `on_*_line` у команды прогоняет
  canned-строки через них — ваш `fetch_with_progress` (`git fetch --progress`
  + `on_stderr_line`) тестируется герметично как есть.

### 2.4 Сверх спеки: `ProcessRunner::start` на шве + scripted streaming

`start()` теперь **на трейте** (дефолт — `Error::Unsupported`, ваши кастомные
runner'ы и кассеты компилируются без правок). `ScriptedRunner::start` отдаёт
**скриптед `RunningProcess`**, чей canned-вывод идёт через ту же pump-машинерию,
что и реальный ребёнок — `stdout_lines` / `wait_for_line` / `finish_streamed`
работают без сабпроцесса:

```rust
let runner = ScriptedRunner::new()
    .on(["run", "watch"],
        Reply::lines(["queued", "in_progress", "completed"])
            .with_line_delay(Duration::from_millis(100))); // пейсинг, paused-clock-friendly
let mut run = runner.start(&gh.core.command(["run", "watch", id])).await?;
run.wait_for_line(|l| l.contains("completed"), limit).await?;
let (code, _) = run.finish_streamed().await?;
```

Границы (честные, документированы): scripted-handle **без pid**, не компонуется
в реальный `Pipeline`, не моделирует интерактивный stdin; streaming-кассеты пока
не пишутся. `RecordingRunner` записывает `start`-инвокации.

### 2.5 `ProcessResult::outcome()` — для классификаторов vcs-cli-support

Явный `Outcome::{Exited(i32), Signalled, TimedOut}` вместо ментальной дешифровки
пары `code()/timed_out()`. Аксессоры (`code`/`timed_out`/`is_success`) не
менялись — **миграция не нужна**; берите для новых матчей:

```rust
// vcs-cli-support: классификатор транзиентности читается чище
match result.outcome() {
    Outcome::TimedOut => Transience::Retryable,       // дедлайн — ретраим
    Outcome::Signalled => Transience::Terminal,       // сигнал — не транзиентно
    Outcome::Exited(c) if is_transient_code(c) => Transience::Retryable,
    Outcome::Exited(_) => Transience::Terminal,
    _ => Transience::Terminal,                         // non_exhaustive
}
```

`Outcome` — `#[non_exhaustive]`, держите catch-all.

### 2.6 Пайплайны: `unchecked()` и оператор `|`

- `Command::unchecked()` — исключает стадию из pipefail-атрибуции: её
  «грязный» выход (non-zero, сигнал/SIGPIPE, per-stage-timeout) пропускается при
  обвинении цепочки. Чинит ложный fail `producer | head -1` (producer умирает от
  SIGPIPE, когда head закрывает pipe). Checked-сбой всегда бьёт unchecked; цепочка,
  где все сбои unchecked, — успех. Если в plumbing'е (`git cat-file --batch | …`)
  верхняя стадия легитимно обрывается ранним консьюмером — пометьте её
  `.unchecked()`.
- `a | b | c` — сахар для `a.pipe(b).pipe(c)` (та же shell-free группа,
  pipefail). Скобки перед терминальным вербом: `(a | b | c).run()`.

### 2.7 Надёжность и `tracing`

- **Расширенный `tracing`** (фича): события spawn/timeout/cancel/terminate/
  shutdown/retry/adopt, паники пампов, сбои stdin-writer'а — target
  `"processkit"`, **argv/env не логируются**. Полезно включить в vcs-mcp-сервере
  для наблюдаемости длинных прогонов.
- **stdin-writer ошибки** больше не теряются молча (warn вместо тишины; EPIPE —
  штатный случай, не логируется).
- **Фикс hang:** `keep_stdin_open` + bulk-верб (`run`/`output_string`/…) больше
  не вешает читающего stdin ребёнка — невзятый интерактивный pipe закрывается
  при потреблении (ребёнок видит EOF). Если где-то ставили `keep_stdin_open`, но
  гоняли bulk-вербом без `standard_input()` — теперь это безопасно (раньше
  висло до таймаута).
- **`Command::kill_on_parent_death()`** — опт-ин: ребёнок умирает при резкой
  смерти родителя (SIGKILL, где Drop не бежит). Windows гарантирует это и так
  (Job kill-on-close), Linux армит PDEATHSIG на прямого ребёнка
  (PID-1-контейнер-safe), macOS — no-op. Для vcs-toolkit маргинально (kill-on-drop
  уже покрывает штатные пути), но если vcs-mcp-сервер форкает долгоживущие
  watch'и — рассмотрите.

### 2.8 Супервизор: storm-guard (если оркестрируете)

`Supervisor::storm_pause` / `failure_decay` / `failure_threshold` — опт-ин
анти-шторм: каждый сбой кормит счётчик, что распадается каждые `failure_decay`;
за порогом — одна джиттерованная пауза вместо долбёжки рестартами. Различает
«редко падает» и «штормит». Off by default; паузы — в
`SupervisionOutcome::storm_pauses`. Релевантно vcs-mcp, если он держит
долгоживущие процессы.

### 2.9 НОВОЕ в 0.8.2: ограниченный фан-аут — `output_all` / `wait_all`

Если где-то гоняете ОДНУ команду по многим целям (статус по N репо в фасаде
`vcs-core`, `gh api` по списку PR/issue, пламбинг по набору объектов) — два
core-примитива (без фич), вместо наивного `futures::join_all` без тормозов:

- `output_all(commands, concurrency, &runner) -> Vec<Result<ProcessResult<String>>>` —
  запускает батч, держа живыми **не более `concurrency`** процессов разом
  (защита от исчерпания fd/таблицы pid, которой у `join_all` нет). **Collect-all:**
  ненулевой выход — это `Ok(ProcessResult)` с кодом, не `Err`; батч никогда не
  коротит, вызывающий сам сворачивает исходы (как наша «status is data»-линия).
  Передайте `&group` (общая kill-on-drop группа на весь батч) или `&JobRunner`
  (приватная группа на каждую команду).
- `wait_all(&mut [&mut RunningProcess]) -> Result<Vec<Option<i32>>>` — джойн-
  компаньон `wait_any`: дожидается ВСЕХ хендлов, коды в порядке входа (пустой
  срез → пустой `Vec`).

Важно: `output_all` **не** cancel-safe (владеет порождёнными детьми — дроп
future рвёт незавершённые деревья), в отличие от `wait_all`/`wait_any`. Это
**не** пул/шедулер/ретраер: ретраи стройте через `retry` на отдельных командах,
не на батче. Для чисто one-shot обёрток без массовых операций — на полку.

---

## 3. Что НЕ появилось (осознанные отказы)

- **`on_command` / `default_map`-хук** (streaming-спека R4, cancellation-спека
  R3) — отклонён: типизированные узкие default'ы
  (`default_timeout`/`default_env`/`default_cancel_on`) бьют хранимую замыкалку
  по интроспекции (`Debug`), документируемости и прозрачности кассет. Ревизит —
  если накопится **третий** типизированный кандидат «применить к каждой
  команде», тогда одним дизайном.
- **Streaming-кассеты** — future (нужно расширение схемы под тайминг/форму
  стрима). Поднимайте спекой, если упрётесь; пока для герметичного стриминга —
  `ScriptedRunner::start` (§2.4).

---

## 4. Чек-лист апгрейда

1. `[workspace.dependencies] processkit = "0.8"` (+ `features = ["cancellation"]`
   там, где берёте §2.1/§2.2; `record`/`tracing`/`mock` по необходимости).
2. `cargo update -p processkit`; в `Cargo.lock` — ровно один processkit и один
   `windows-sys`.
3. **Find-replace вербов** §1.1 (только получатели-клиенты, не `result.code()`);
   компиляция = чек-лист.
4. Проверить отсутствие исчерпывающих матчей/литералов `SupervisionOutcome`;
   обновить тесты, ассертящие точный текст `Error::Exit` Display (§1.3).
5. clippy `-D warnings`; тесты с `--include-ignored` на всех трёх ОС.
6. Снять собственные каветки «streaming/cancel не тестируется герметично» —
   добавить герметичные тесты: прогресс-путей (R3, §2.3), отмены
   (`Reply::pending`, §2.2), `gh run watch`-оркестрации (`start`, §2.4).
7. Классификаторы vcs-cli-support: перечитать на `Outcome` (§2.5), добавить
   тест-кейс `Outcome::TimedOut`/`Signalled`.
8. CHANGELOG vcs-*: бамп ре-экспортируемого processkit = breaking; выпустить
   согласованно; сообщить консьюмерам версии vcs-* с processkit 0.8.

---

## 5. Ответ processkit на `processkit-client-cancellation-spec.md` (дословно)

> Включено по запросу — исходник в
> `d:\GitHub\Personal\Ideas\Requests\processkit-client-cancellation-spec.md`.

**R1 — ACCEPTED, implemented.** `CliClient::default_cancel_on(token)` behind
the `cancellation` feature, applied in `apply_defaults` alongside
`default_timeout`/`default_env`. **Precedence chosen: override** — the default
is applied when the command is built, so a per-command `cancel_on` chained on
the returned command *replaces* it (explicit beats default, exactly like a
per-command `timeout` after `default_timeout`); compose via `child_token()`
when both must fire. `cli_client!` re-emits the builder on generated wrappers
(via an internal feature-selected helper macro, so the cfg is evaluated
against processkit's features, not the downstream crate's). Both acceptance
tests shipped: a real hanging child cancelled through a client default
(integration), and the precedence pin (hermetic).

**R2 — ACCEPTED, implemented.** `Reply::pending()` (`cancellation` feature):
`ScriptedRunner` parks the matched call until the command's token — per-command
or client default — fires, then resolves `Err(Error::Cancelled { program })`.
`RecordingRunner` records the invocation before delegating (unchanged). A
pending reply for a command with **no** token parks forever (documented:
behaves like a hung child nobody can cancel). The spec's acceptance test is in
processkit's suite verbatim (`run watch` + `default_cancel_on`).

**R3 — DECLINED.** A typed, narrow default wins over a stored
`Fn(Command) -> Command` closure for introspection (`Debug`), documentation,
and cassette/recording transparency; R1 covers the stated need. Revisit only
if a *third* typed "apply to every command" candidate accumulates — then fold
the streaming-spec's R4 into one design rather than shipping either piecemeal.

**Ships in:** **0.8.0** (also carries an unrelated breaking change,
`SupervisionOutcome` becoming `#[non_exhaustive]`). MSRV unchanged (1.88). Pin
`processkit = "0.8"` with `features = ["cancellation"]`.
