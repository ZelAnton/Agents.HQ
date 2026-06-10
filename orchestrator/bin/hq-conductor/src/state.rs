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
        Self { hq, orch, runs, lock, lock5, status, status_template, schemas }
    }

    /// Родительская директория .hq (Personal/).
    pub fn personal(&self) -> &Path {
        self.hq.parent().unwrap_or(&self.hq)
    }
}

/// Список run-директорий (последние `window`, в хронологическом порядке по имени).
pub fn list_run_dirs(runs: &Path, window: usize) -> Vec<PathBuf> {
    let mut dirs: Vec<PathBuf> = std::fs::read_dir(runs)
        .into_iter()
        .flatten()
        .flatten()
        .map(|e| e.path())
        .filter(|p| p.is_dir())
        .collect();
    dirs.sort();
    if dirs.len() > window {
        dirs = dirs[dirs.len() - window..].to_vec();
    }
    dirs
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
