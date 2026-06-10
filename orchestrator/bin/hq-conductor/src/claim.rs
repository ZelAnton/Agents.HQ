use crate::fm::{fm_get, fm_remove, fm_set, parse_fm, render_fm};
use crate::state::{current_hostname, is_pid_alive};
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

            // Есть claim — проверяем lease expiry
            let lease_expired = fm_get(&pairs, "lease-until")
                .as_deref()
                .and_then(|s| chrono::DateTime::parse_from_rfc3339(s).ok())
                .map(|t| chrono::Utc::now() > t.to_utc())
                .unwrap_or(true); // нет поля → считаем истёкшим

            if !lease_expired {
                eprintln!(
                    "claimed: assigned-to={assigned}, lease active until {}",
                    fm_get(&pairs, "lease-until").unwrap_or_default()
                );
                std::process::exit(1);
            }

            // Lease истёк → проверяем, мёртв ли owner PID (только на том же хосте)
            let owner_host = fm_get(&pairs, "owner-host").unwrap_or_default();
            let owner_pid: Option<u32> = fm_get(&pairs, "owner-pid").and_then(|s| s.parse().ok());
            let same_host = owner_host.eq_ignore_ascii_case(&current_hostname());

            let pid_confirmed_dead = if same_host {
                owner_pid.map(|p| !is_pid_alive(p)).unwrap_or(false)
            } else {
                false // другой хост → не можем проверить
            };

            if lease_expired && pid_confirmed_dead {
                println!("free (lease expired, owner confirmed dead)");
                return Ok(());
            } else {
                // fail-closed: не можем подтвердить смерть → эскалация (§11.5)
                eprintln!(
                    "claimed: assigned-to={assigned}, lease_expired={lease_expired} \
                     pid_confirmed_dead={pid_confirmed_dead} same_host={same_host} (fail-closed)"
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
