//! M3 — real-agent worker spawning. The tick builds per-role jobs, runs them through
//! `hq-spawn` (bounded concurrency + timeout + kill-on-drop), then reads each worker's
//! structured result file and decides the next state. Risk assessment and DEC creation
//! live here (Rust owns routing; land.ps1 is NOT modified — isolation per M3 decision).

use serde::{Deserialize, Deserializer};
use std::path::{Path, PathBuf};

// ---------- hq-spawn job protocol ----------

pub struct Job {
    pub id: String,
    pub program: String,
    pub args: Vec<String>,
    pub timeout_sec: u64,
}

/// hq-spawn writes `"code": null` for timed-out or spawn-error jobs.
/// Treat null as -1 (conventional "no exit code") to avoid deserialization failure.
fn de_nullable_i32<'de, D: Deserializer<'de>>(d: D) -> Result<i32, D::Error> {
    Ok(Option::<i32>::deserialize(d)?.unwrap_or(-1))
}

/// PowerShell's ConvertTo-Json serializes empty arrays `@()` as `null` in some
/// contexts. Treat null as an empty Vec to avoid deserialization failure.
fn de_nullable_vec<'de, D: Deserializer<'de>>(d: D) -> Result<Vec<String>, D::Error> {
    Ok(Option::<Vec<String>>::deserialize(d)?.unwrap_or_default())
}

#[derive(Deserialize, Debug, Default, Clone)]
pub struct JobResult {
    pub id: String,
    #[serde(default, deserialize_with = "de_nullable_i32")]
    pub code: i32,
    #[serde(default)]
    pub success: bool,
    #[serde(default)]
    pub timed_out: bool,
    #[serde(default)]
    pub ms: u64,
    #[serde(default)]
    pub stdout_tail: String,
    #[serde(default)]
    pub stderr_tail: String,
}

/// Write jobs.json, run hq-spawn, read results.json. Returns one JobResult per job.
/// hq-spawn's own exit code is ignored — per-job success is read from results.json.
pub fn run_batch(
    spawn_bin: &Path,
    jobs: &[Job],
    limit: usize,
    batch_dir: &Path,
) -> Result<Vec<JobResult>, Box<dyn std::error::Error>> {
    std::fs::create_dir_all(batch_dir)?;
    let jobs_json: Vec<serde_json::Value> = jobs
        .iter()
        .map(|j| {
            serde_json::json!({
                "id": j.id,
                "program": j.program,
                "args": j.args,
                "timeout_sec": j.timeout_sec,
            })
        })
        .collect();
    let jobs_file = batch_dir.join("jobs.json");
    let results_file = batch_dir.join("results.json");
    std::fs::write(&jobs_file, serde_json::to_string_pretty(&jobs_json)?)?;

    let limit = limit.max(1);
    let status = std::process::Command::new(spawn_bin)
        .arg("--jobs")
        .arg(&jobs_file)
        .arg("--limit")
        .arg(limit.to_string())
        .arg("--out")
        .arg(&results_file)
        .status();
    match status {
        Ok(_) => {}
        Err(e) => return Err(format!("не удалось запустить hq-spawn ({}): {e}", spawn_bin.display()).into()),
    }

    let text = std::fs::read_to_string(&results_file)
        .map_err(|e| format!("hq-spawn не записал results.json в {}: {e}", results_file.display()))?;
    let results: Vec<JobResult> = serde_json::from_str(&text)?;
    Ok(results)
}

/// Log any failed/timed-out jobs from a batch (stderr tail aids real-agent debugging in M3b).
pub fn log_failed_jobs(results: &[JobResult], phase: &str) {
    for r in results.iter().filter(|r| !r.success || r.timed_out) {
        let why = if r.timed_out { "timeout" } else { "exit≠0" };
        let tail = r.stderr_tail.trim();
        let tail = if tail.is_empty() { r.stdout_tail.trim() } else { tail };
        eprintln!("  [{phase}] job {} {why} (code={}, {}ms): {tail}", r.id, r.code, r.ms);
    }
}

// ---------- worker result files ----------

/// `summary.json` written by exec-one.ps1.
#[derive(Deserialize, Debug, Default)]
pub struct ExecSummary {
    #[serde(default)]
    pub repo: String,
    #[serde(default)]
    pub workspace: String,
    #[serde(default)]
    pub dest: String,
    #[serde(default)]
    pub executor_status: Option<String>,
    #[serde(default)]
    pub gate_build: bool,
    #[serde(default)]
    pub gate_tests: bool,
    #[serde(default, deserialize_with = "de_nullable_vec")]
    pub out_of_scope: Vec<String>,
    #[serde(default, deserialize_with = "de_nullable_vec")]
    pub leaks: Vec<String>,
    #[serde(default)]
    pub exec_error: Option<String>,
}

pub fn read_exec_summary(run_dir: &Path) -> Option<ExecSummary> {
    let text = std::fs::read_to_string(run_dir.join("summary.json")).ok()?;
    serde_json::from_str(&text).ok()
}

/// `verify.json` written by verify-one.ps1 (hq-verify output).
#[derive(Deserialize, Debug, Default)]
pub struct VerifyResult {
    #[serde(default)]
    pub verdict: String, // pass | fail
    #[serde(default)]
    pub dod_met: bool,
    #[serde(default, deserialize_with = "de_nullable_vec")]
    pub out_of_scope: Vec<String>,
    #[serde(default)]
    pub findings: Vec<VerifyFinding>,
    #[serde(default)]
    pub summary: String,
}

#[derive(Deserialize, Debug, Default, Clone)]
pub struct VerifyFinding {
    #[serde(default)]
    pub sev: String,
    #[serde(default)]
    pub msg: String,
}

pub fn read_verify(run_dir: &Path) -> Option<VerifyResult> {
    let text = std::fs::read_to_string(run_dir.join("verify.json")).ok()?;
    serde_json::from_str(&text).ok()
}

/// `review-context.json` written by verify-one.ps1 — workspace facts the Rust risk()
/// needs (computed by the PS worker that has jj access). Keeps risk logic in Rust while
/// not shelling jj from the conductor.
#[derive(Deserialize, Debug, Default)]
pub struct ReviewContext {
    #[serde(default)]
    pub change: String,
    #[serde(default, deserialize_with = "de_nullable_vec")]
    pub changed_files: Vec<String>,
    #[serde(default)]
    pub diff_lines: u64,
    #[serde(default)]
    pub has_conflict: bool,
    #[serde(default)]
    pub is_empty: bool,
    #[serde(default, deserialize_with = "de_nullable_vec")]
    pub leaks: Vec<String>,
}

pub fn read_review_context(run_dir: &Path) -> Option<ReviewContext> {
    let text = std::fs::read_to_string(run_dir.join("review-context.json")).ok()?;
    serde_json::from_str(&text).ok()
}

/// `plan-result.json` written by plan-one.ps1.
#[derive(Deserialize, Debug, Default)]
pub struct PlanResult {
    #[serde(default)]
    pub decision: String, // accept | reject | escalate
    #[serde(default)]
    pub reason: String,
}

pub fn read_plan_result(run_dir: &Path) -> Option<PlanResult> {
    let text = std::fs::read_to_string(run_dir.join("plan-result.json")).ok()?;
    serde_json::from_str(&text).ok()
}

// ---------- risk() — ported from land.ps1, fail-closed ----------

/// Sensitive-path patterns (subset of land.ps1 $SensitiveRx) — a change touching any of
/// these is never auto-landed.
fn is_sensitive(path: &str) -> bool {
    let p = path.replace('\\', "/").to_ascii_lowercase();
    const NEEDLES: &[&str] = &[
        "/.github/", ".github/", "/.gitlab", "cargo.toml", "cargo.lock", ".csproj", ".fsproj",
        ".vbproj", ".sln", ".props", ".targets", ".nuspec", "/.env", ".npmrc", ".pypirc",
        "secret", "credential", "/migration", "changelog.md", ".yml", ".yaml",
    ];
    NEEDLES.iter().any(|n| p.contains(n))
}

#[derive(Debug)]
pub struct RiskVerdict {
    pub low: bool,
    pub reasons: Vec<String>,
}

/// Deterministic fail-closed risk(). `size_limit` = max diff lines for low risk.
pub fn assess_risk(
    summary: &ExecSummary,
    verify: Option<&VerifyResult>,
    ctx: &ReviewContext,
    size_limit: u64,
) -> RiskVerdict {
    let mut reasons = Vec::new();
    if ctx.is_empty {
        reasons.push("изменение пустое".to_owned());
    }
    if ctx.has_conflict {
        reasons.push("нерешённые jj-конфликты".to_owned());
    }
    if !summary.gate_build {
        reasons.push("build не зелёный".to_owned());
    }
    if !summary.gate_tests {
        reasons.push("tests не зелёные".to_owned());
    }
    match verify {
        None => reasons.push("Верификатор недоступен/ошибка".to_owned()),
        Some(v) => {
            if v.verdict != "pass" {
                reasons.push(format!("Верификатор verdict={}", v.verdict));
            }
            if !v.dod_met {
                reasons.push("DoD не покрыт".to_owned());
            }
        }
    }
    let verify_oos = verify.map(|v| v.out_of_scope.clone()).unwrap_or_default();
    if !summary.out_of_scope.is_empty() || !verify_oos.is_empty() {
        let all: Vec<String> = summary.out_of_scope.iter().chain(verify_oos.iter()).cloned().collect();
        reasons.push(format!("выход за scope: {}", all.join(", ")));
    }
    let sensitive: Vec<String> = ctx.changed_files.iter().filter(|f| is_sensitive(f)).cloned().collect();
    if !sensitive.is_empty() {
        reasons.push(format!("чувствительные пути: {}", sensitive.join(", ")));
    }
    if ctx.diff_lines > size_limit {
        reasons.push(format!("объём {} строк > порога {size_limit}", ctx.diff_lines));
    }
    let leaks: Vec<String> = summary.leaks.iter().chain(ctx.leaks.iter()).cloned().collect();
    if !leaks.is_empty() {
        reasons.push(format!("возможные утечки: {}", leaks.join(", ")));
    }
    RiskVerdict { low: reasons.is_empty(), reasons }
}

/// Did the verifier fail in a way a re-exec could fix (verdict=fail or DoD unmet)?
pub fn verify_is_fixable(verify: Option<&VerifyResult>) -> bool {
    match verify {
        Some(v) => v.verdict == "fail" || !v.dod_met,
        None => false, // no verify result → not a "fixable" review, treat as escalate
    }
}

// ---------- DEC creation (ported from land.ps1 escalation path) ----------

/// Next DEC id by scanning the decisions dir for `DEC-####`.
fn next_dec_id(decisions: &Path) -> String {
    let mut max = 0u32;
    if let Ok(entries) = std::fs::read_dir(decisions) {
        for e in entries.flatten() {
            if let Some(name) = e.file_name().to_str() {
                if let Some(rest) = name.strip_prefix("DEC-") {
                    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
                    if let Ok(n) = digits.parse::<u32>() {
                        max = max.max(n);
                    }
                }
            }
        }
    }
    format!("DEC-{:04}", max + 1)
}

fn slugify(s: &str, max: usize) -> String {
    let mut out: String = s
        .chars()
        .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_lowercase() } else { '-' })
        .collect();
    while out.contains("--") {
        out = out.replace("--", "-");
    }
    let out = out.trim_matches('-').to_owned();
    if out.len() > max { out[..max].trim_end_matches('-').to_owned() } else { out }
}

pub struct DecInfo {
    pub id: String,
    pub file: PathBuf,
}

/// Write a land DEC for an escalated review. Returns the DEC id + path. Mirrors the
/// frontmatter land.ps1 emits so `land.ps1 -Resume <DEC>` can still consume it.
#[allow(clippy::too_many_arguments)]
pub fn write_land_dec(
    decisions: &Path,
    inbox: &Path,
    task_id: &str,
    repo: &str,
    workspace: &str,
    dest: &str,
    change: &str,
    remote: &str,
    risk: &str,
    reasons: &[String],
    findings: &[VerifyFinding],
    now_date: &str,
) -> Result<DecInfo, Box<dyn std::error::Error>> {
    std::fs::create_dir_all(decisions)?;
    let id = next_dec_id(decisions);
    let slug = slugify(repo, 24);
    let file = decisions.join(format!("{id}-land-{slug}.md"));

    let reason_list = if reasons.is_empty() {
        "- (risk low, но autonomy ≠ auto-low — нужно согласие)".to_owned()
    } else {
        reasons.iter().map(|r| format!("- {r}")).collect::<Vec<_>>().join("\n")
    };
    let findings_list = if findings.is_empty() {
        "- (нет замечаний Верификатора)".to_owned()
    } else {
        findings.iter().map(|f| format!("- [{}] {}", f.sev, f.msg)).collect::<Vec<_>>().join("\n")
    };
    let recommended = if risk == "low" { "A" } else { "null" };

    let dec = format!(
        "---\nid: {id}\ntype: decision\ntitle: Приземлять ли изменение в {repo} ({change})?\n\
         date: {now_date}\nfrom: hq-conductor/tick\npriority: P1\nstatus: open\nblocks: []\n\
         from-thread: null\nland-task: {task_id}\nland-repo: {repo}\nland-workspace: {workspace}\n\
         land-dest: {dest}\nland-change: {change}\nland-remote: {remote}\nland-risk: {risk}\n\
         consumed-at: null\noptions:\n  - id: A\n    label: land — приземлить (advance main + push)\n\
         \x20 - id: B\n    label: abandon — откатить (forget workspace, без land)\n\
         recommended: {recommended}\n\nanswer:\n  decision: null        # A | B | other\n\
         \x20 note: null\n  by: anton\n  date: null\n---\n\n\
         ## Контекст\nОркестратор (hq-conductor tick) исполнил {task_id} в workspace `{workspace}` \
         (репо **{repo}**), прогнал гейт и Верификатор. Авто-приземление НЕ выполнено: `risk={risk}`.\n\n\
         **Изменение** `{change}`.\n\n## Почему не приземлено автоматически\n{reason_list}\n\n\
         ## Замечания Верификатора\n{findings_list}\n\n## Что делать\n\
         - Проверь diff: `cd \"{dest}\"; jj diff`\n\
         - **A (land):** `decision: A` + `status: answered` → `pwsh land.ps1 -Resume {id}`\n\
         - **B (abandon):** `decision: B` + `status: answered` → `pwsh land.ps1 -Resume {id}`\n",
    );
    std::fs::write(&file, dec)?;

    // best-effort INBOX index line
    append_inbox_line(inbox, &id, repo, change, &file);

    Ok(DecInfo { id, file })
}

fn append_inbox_line(inbox: &Path, dec_id: &str, repo: &str, change: &str, dec_file: &Path) {
    let Ok(content) = std::fs::read_to_string(inbox) else { return };
    if content.contains(dec_id) {
        return; // already indexed (idempotent)
    }
    let fname = dec_file.file_name().and_then(|s| s.to_str()).unwrap_or("");
    let line = format!("| {dec_id} | P1 | Land {repo} ({change})? | — | `human/decisions/{fname}` |");

    // Replace the "_пока нет_" placeholder row if present (parity with land.ps1); else append.
    let is_placeholder = |l: &str| l.contains("_пока нет_") && l.trim_start().starts_with('|');
    let trailing_nl = content.ends_with('\n');
    let mut lines: Vec<String> = content.lines().map(|s| s.to_owned()).collect();
    if let Some(pos) = lines.iter().position(|l| is_placeholder(l)) {
        lines[pos] = line;
    } else {
        lines.push(line);
    }
    let mut out = lines.join("\n");
    if trailing_nl {
        out.push('\n');
    }
    let _ = std::fs::write(inbox, out);
}
