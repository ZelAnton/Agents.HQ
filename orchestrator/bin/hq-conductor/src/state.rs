use std::path::{Path, PathBuf};

/// Ищет корень .hq вверх от cwd — директорию, у которой есть `orchestrator/_runs/`.
pub fn find_hq_root() -> Option<PathBuf> {
    let cwd = std::env::current_dir().ok()?;
    let mut cur: &Path = &cwd;
    loop {
        if cur.join("orchestrator").join("_runs").is_dir() {
            return Some(cur.to_path_buf());
        }
        cur = cur.parent()?;
    }
}

/// Канонические пути внутри .hq.
#[allow(dead_code)]
pub struct Paths {
    pub hq: PathBuf,
    pub orch: PathBuf,
    pub runs: PathBuf,
    pub lock: PathBuf,
    pub lock5: PathBuf,
    pub status: PathBuf,
    pub status_template: PathBuf,
    pub schemas: PathBuf,
    pub sessions_active: PathBuf,
    pub sessions_archive: PathBuf,
    pub tasks: PathBuf,
    /// `orchestrator/automation.json` — pause / policy overrides
    pub automation_json: PathBuf,
}

impl Paths {
    pub fn new(hq: PathBuf) -> Self {
        let orch = hq.join("orchestrator");
        let runs = orch.join("_runs");
        let lock = orch.join(".lock");
        let lock5 = orch.join(".lock5");
        let status = orch.join("STATUS.md");
        let status_template = orch.join("STATUS.template.md");
        let schemas = orch.join("schemas");
        let sessions_active = orch.join("sessions").join("active");
        let sessions_archive = orch.join("sessions").join("_archive");
        let tasks = hq.join("tasks");
        let automation_json = orch.join("automation.json");
        Self { hq, orch, runs, lock, lock5, status, status_template, schemas, sessions_active, sessions_archive, tasks, automation_json }
    }

    /// Родительская директория .hq (Personal/).
    pub fn personal(&self) -> &Path {
        self.hq.parent().unwrap_or(&self.hq)
    }
}

/// Рекурсивный обход файлов в директории.
pub fn walk_files(dir: &Path) -> Vec<PathBuf> {
    let mut out = Vec::new();
    walk_inner(dir, &mut out);
    out
}

fn walk_inner(dir: &Path, out: &mut Vec<PathBuf>) {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for e in entries.flatten() {
            let p = e.path();
            if p.is_dir() {
                walk_inner(&p, out);
            } else {
                out.push(p);
            }
        }
    }
}

/// Содержимое файла замка: `<PID>\t<ISO-timestamp>`.
#[derive(Debug)]
pub struct LockInfo {
    pub pid: u32,
    pub started_iso: String,
    #[allow(dead_code)]
    pub path: PathBuf,
}

impl LockInfo {
    pub fn read(path: &Path) -> Option<Self> {
        let text = std::fs::read_to_string(path).ok()?;
        let text = text.trim();
        let (pid_str, ts) = text.split_once('\t')?;
        let pid: u32 = pid_str.trim().parse().ok()?;
        Some(Self { pid, started_iso: ts.trim().to_owned(), path: path.to_path_buf() })
    }

    /// Возраст > 60 мин → stale.
    pub fn is_stale(&self) -> bool {
        chrono::DateTime::parse_from_rfc3339(&self.started_iso)
            .map(|t| {
                let age = chrono::Utc::now().signed_duration_since(t.to_utc());
                age.num_minutes() > 60
            })
            .unwrap_or(true) // не парсится → stale
    }

    pub fn is_pid_alive(&self) -> bool {
        is_pid_alive(self.pid)
    }
}

/// Жив ли процесс по PID (Windows: tasklist; fail-closed → true если не можем проверить).
pub fn is_pid_alive(pid: u32) -> bool {
    let out = std::process::Command::new("tasklist")
        .args(["/FI", &format!("PID eq {pid}"), "/NH", "/FO", "CSV"])
        .output()
        .ok();
    match out {
        None => true, // fail-closed: не можем проверить → считаем живым
        Some(o) => {
            let s = String::from_utf8_lossy(&o.stdout);
            s.contains(&format!("\"{pid}\""))
        }
    }
}

/// Текущее имя хоста (Windows: COMPUTERNAME; Unix: HOSTNAME).
pub fn current_hostname() -> String {
    std::env::var("COMPUTERNAME")
        .or_else(|_| std::env::var("HOSTNAME"))
        .unwrap_or_default()
}

/// Абсолютный потолок: если lease просрочен больше чем на это время, ресурс
/// освобождается ДАЖЕ если PID выглядит живым (защита от переиспользования PID
/// мёртвого прогона живым процессом — иначе задача/сессия зависает навсегда).
pub const FORCE_RELEASE_GRACE_SEC: i64 = 3 * 3600;

/// Единая логика «владелец lease мёртв → ресурс можно забрать». Используется и для
/// claim задач (dispatch::task_is_free), и для сессий (session::gc), чтобы они не
/// расходились. Семантика:
/// - тот же хост + PID точно мёртв → забрать сразу (быстрое восстановление после краха);
/// - тот же хост + PID жив (возможно переиспользован) → только после lease + FORCE_GRACE;
/// - тот же хост без PID → по истечении lease;
/// - другой хост (PID не проверить, fail-closed) → только после lease + FORCE_GRACE;
/// - claimed, но lease отсутствует, и владелец не подтверждён мёртвым → НЕ забирать.
pub fn owner_reclaimable(
    owner_host: &str,
    owner_pid: Option<u32>,
    lease_until: Option<chrono::DateTime<chrono::Utc>>,
) -> bool {
    let now = chrono::Utc::now();
    let same_host = owner_host.eq_ignore_ascii_case(&current_hostname());

    // Проверяем PID РОВНО ОДИН раз (каждый is_pid_alive порождает `tasklist`), кешируем:
    // Some(true)=жив · Some(false)=мёртв · None=не проверяли (другой хост или нет PID).
    let pid_alive: Option<bool> = if same_host { owner_pid.map(is_pid_alive) } else { None };

    // Быстрый путь: на своём хосте PID точно мёртв → забрать немедленно (без ожидания lease).
    if pid_alive == Some(false) {
        return true;
    }

    match lease_until {
        Some(lease) => {
            let force = now > lease + chrono::Duration::seconds(FORCE_RELEASE_GRACE_SEC);
            if same_host {
                if pid_alive == Some(true) {
                    // PID выглядит живым (мог быть переиспользован) → только по force-grace
                    force
                } else {
                    // same_host, но PID не задан → доверяем таймауту lease
                    now > lease
                }
            } else {
                // другой хост → не можем проверить → fail-closed до force-grace
                force
            }
        }
        // claimed, но lease нет; мёртвый PID уже обработан выше → fail-closed
        None => false,
    }
}
