use crate::fm::{fm_get, fm_remove, fm_set, parse_fm, render_fm};
use crate::state::{current_hostname, owner_reclaimable};
use clap::{Args, Subcommand};
use std::path::PathBuf;

#[derive(Args)]
pub struct ClaimArgs {
    #[command(subcommand)]
    pub action: ClaimAction,
}

#[derive(Subcommand)]
pub enum ClaimAction {
    /// Записать lease/claim во frontmatter задачи
    Write {
        task: PathBuf,
        #[arg(long)]
        owner: String,
        /// Ожидаемое время выполнения (сек)
        #[arg(long, default_value = "900")]
        timeout_sec: u64,
        /// Grace-период сверх timeout (сек)
        #[arg(long, default_value = "300")]
        grace_sec: u64,
    },
    /// Проверить доступность задачи (exit 0 = свободна, exit 1 = занята/fail-closed)
    Check {
        task: PathBuf,
    },
    /// Освободить claim (сбросить поля lease)
    Release {
        task: PathBuf,
    },
}

// ---------- command handler ----------

pub fn run(_hq: PathBuf, args: ClaimArgs) -> Result<(), Box<dyn std::error::Error>> {
    match args.action {
        ClaimAction::Write { task, owner, timeout_sec, grace_sec } => {
            let content = std::fs::read_to_string(&task)?;
            let (mut pairs, body_start) = parse_fm(&content);
            let body = &content[body_start..];

            let now = chrono::Utc::now();
            // lease ≥ timeout, чтобы lease не истёк до окончания выполнения (§11.5)
            let lease_until = now + chrono::Duration::seconds((timeout_sec + grace_sec) as i64);

            fm_set(&mut pairs, "assigned-to", &owner);
            fm_set(&mut pairs, "claimed-at", &now.to_rfc3339());
            fm_set(&mut pairs, "lease-until", &lease_until.to_rfc3339());
            fm_set(&mut pairs, "owner-pid", &std::process::id().to_string());
            fm_set(&mut pairs, "owner-host", &current_hostname());

            std::fs::write(&task, render_fm(&pairs, body))?;
            println!("claimed: {} until {}", task.display(), lease_until.to_rfc3339());
        }

        ClaimAction::Check { task } => {
            let content = std::fs::read_to_string(&task)?;
            let (pairs, _) = parse_fm(&content);

            let assigned = fm_get(&pairs, "assigned-to").unwrap_or_default();
            if assigned.is_empty() || assigned == "null" {
                println!("free");
                return Ok(());
            }

            // ЕДИНЫЙ источник правды с тиком (dispatch::task_is_free) — owner_reclaimable.
            // Раньше здесь была отдельная (более строгая) логика, расходившаяся с tick:
            // claim check мог вечно держать «claimed» задачу, которую tick уже забрал по
            // force-grace (переиспользование PID / другой хост / истёкший lease без PID).
            let owner_host = fm_get(&pairs, "owner-host").unwrap_or_default();
            let owner_pid: Option<u32> = fm_get(&pairs, "owner-pid").and_then(|s| s.parse().ok());
            let lease_until = fm_get(&pairs, "lease-until")
                .as_deref()
                .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                .map(|t| t.to_utc());

            if owner_reclaimable(&owner_host, owner_pid, lease_until) {
                println!("free (owner gone / lease forfeited)");
            } else {
                eprintln!(
                    "claimed: assigned-to={assigned}, lease until {} (owner alive / в grace)",
                    fm_get(&pairs, "lease-until").unwrap_or_else(|| "—".to_owned())
                );
                std::process::exit(1);
            }
        }

        ClaimAction::Release { task } => {
            let content = std::fs::read_to_string(&task)?;
            let (mut pairs, body_start) = parse_fm(&content);
            let body = &content[body_start..];

            fm_set(&mut pairs, "assigned-to", "null");
            fm_remove(&mut pairs, "claimed-at");
            fm_remove(&mut pairs, "lease-until");
            fm_remove(&mut pairs, "owner-pid");
            fm_remove(&mut pairs, "owner-host");

            std::fs::write(&task, render_fm(&pairs, body))?;
            println!("released: {}", task.display());
        }
    }
    Ok(())
}
