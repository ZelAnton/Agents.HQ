//! hq-spawn — спавнер исполнителей оркестратора `.hq` (фаза P3).
//!
//! Догфуд `processkit`: запускает СПИСОК команд с ограниченным параллелизмом
//! (`output_all`), пер-командным таймаутом и **kill-on-drop всего дерева процессов**
//! (Windows Job Object) — так что превысивший таймаут исполнитель уносит и свои
//! дочерние (claude/cargo), без орфанов. Сам не решает политику: читает jobs.json,
//! пишет results.json, выходит.
//!
//! Использование:
//!   hq-spawn --jobs <jobs.json> [--out <results.json>] [--limit N]
//!
//! jobs.json:    [{ "id": "...", "program": "pwsh", "args": ["..."], "cwd": "...", "timeout_sec": 600 }]
//! results.json: [{ "id", "code", "success", "timed_out", "ms", "stdout_tail", "stderr_tail" }]

use std::time::{Duration, Instant};

use processkit::{output_all, Command, JobRunner};
use serde::{Deserialize, Serialize};

#[derive(Deserialize)]
struct Job {
    id: String,
    program: String,
    #[serde(default)]
    args: Vec<String>,
    #[serde(default)]
    cwd: Option<String>,
    #[serde(default = "default_timeout")]
    timeout_sec: u64,
}
fn default_timeout() -> u64 {
    600
}

#[derive(Serialize)]
struct Outcome {
    id: String,
    code: Option<i32>,
    success: bool,
    timed_out: bool,
    ms: u128,
    stdout_tail: String,
    stderr_tail: String,
}

/// Последние `max` СИМВОЛОВ (UTF-8-safe), чтобы results.json не разрастался.
fn tail(s: &str, max: usize) -> String {
    let chars: Vec<char> = s.chars().collect();
    if chars.len() <= max {
        s.to_string()
    } else {
        chars[chars.len() - max..].iter().collect()
    }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut jobs_path: Option<String> = None;
    let mut out_path: Option<String> = None;
    let mut limit: usize = 4;
    let mut it = std::env::args().skip(1);
    while let Some(a) = it.next() {
        match a.as_str() {
            "--jobs" => jobs_path = it.next(),
            "--out" => out_path = it.next(),
            "--limit" => limit = it.next().and_then(|v| v.parse().ok()).unwrap_or(4),
            "--help" | "-h" => {
                eprintln!("hq-spawn --jobs <jobs.json> [--out <results.json>] [--limit N]");
                return Ok(());
            }
            other => eprintln!("hq-spawn: игнорирую аргумент '{other}'"),
        }
    }

    let jobs_path = jobs_path.ok_or("--jobs <file> обязателен")?;
    let jobs: Vec<Job> = serde_json::from_str(&std::fs::read_to_string(&jobs_path)?)?;
    let ids: Vec<String> = jobs.iter().map(|j| j.id.clone()).collect();

    let cmds: Vec<Command> = jobs
        .iter()
        .map(|j| {
            let mut c = Command::new(&j.program);
            if !j.args.is_empty() {
                c = c.args(&j.args);
            }
            if let Some(cwd) = &j.cwd {
                c = c.current_dir(cwd);
            }
            c.timeout(Duration::from_secs(j.timeout_sec))
        })
        .collect();

    let t0 = Instant::now();
    // Ограниченный параллелизм + kill-on-drop на каждую команду (JobRunner = свой Job Object).
    let results = output_all(cmds, limit, &JobRunner).await;

    let outs: Vec<Outcome> = results
        .into_iter()
        .zip(ids)
        .map(|(r, id)| match r {
            Ok(pr) => Outcome {
                id,
                code: pr.code(),
                success: pr.is_success(),
                timed_out: pr.timed_out(),
                ms: pr.duration().as_millis(),
                stdout_tail: tail(pr.stdout(), 2000),
                stderr_tail: tail(pr.stderr(), 2000),
            },
            Err(e) => Outcome {
                id,
                code: None,
                success: false,
                timed_out: false,
                ms: 0,
                stdout_tail: String::new(),
                stderr_tail: format!("spawn-error: {e}"),
            },
        })
        .collect();

    let json = serde_json::to_string_pretty(&outs)?;
    if let Some(op) = out_path {
        std::fs::write(&op, &json)?;
    }
    println!("{json}");
    eprintln!(
        "hq-spawn: {} jobs, limit {}, {} ms total",
        outs.len(),
        limit,
        t0.elapsed().as_millis()
    );
    Ok(())
}
