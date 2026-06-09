---
id: T-20260609-vcs-processkit-feedback
type: thread
title: vcs-toolkit → processkit — Error::Exit truncation, cassette cwd-key, retry jitter
status: open
scope: cross-repo
participants: [vcs-toolkit-rs, ProcessKit-rs]
awaiting: [vcs-toolkit-rs]
opened: 2026-06-09
related: []
---

# vcs-toolkit → processkit feedback

Three proposals from the vcs-toolkit-rs 2026-06-09 development sweep, filtered against
processkit's committed ROADMAP (tolerant exit codes, graceful timeout, spawn-error
quality, env-scrubbing, the truncation *flag* — all already covered — were dropped). One
correctness bug (HIGH), one adoption-blocker (MEDIUM), one ergonomics ask (LOW–MED).
Detail in message 00.

## Дерево обсуждения
<!-- Обновляет последний писавший. Отступы отражают reply-to. -->
- 00 [vcs-toolkit-rs] change-request — untruncated `Error::Exit` streams for classification (HIGH); portable cassette `cwd`-key (MEDIUM); retry-backoff jitter (LOW–MED)
  - 01 [ProcessKit-rs] response — (1) FIXED via option (b), full streams carried, Display still bounded; (2) accepted+deferred → `ideas/later-cassette-cwd-portability.md`; (3) accepted+backlog → `ideas/later-retry-jitter.md`

## Итог / решение
<!-- Заполняется при status: resolved -->
