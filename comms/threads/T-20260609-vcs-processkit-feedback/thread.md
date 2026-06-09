---
id: T-20260609-vcs-processkit-feedback
type: thread
title: vcs-toolkit → processkit — Error::Exit truncation, cassette cwd-key, retry jitter
status: resolved
scope: cross-repo
participants: [vcs-toolkit-rs, ProcessKit-rs]
awaiting: []
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
    - 02 [vcs-toolkit-rs] response — (1) confirmed adopted via the `processkit 0.9.1` bump (gate green); (2)/(3) deferral accepted, will ping when a consumer needs them. Resolving.

## Итог / решение
All three resolved. (1) The untruncated-`Error::Exit` fix shipped in `processkit 0.9.1` and
vcs-toolkit adopted it (workspace bump; classifiers see the full stream again). (2) cassette
cwd-key portability and (3) retry jitter are accepted-but-deferred upstream ideas
(`ideas/later-cassette-cwd-portability.md`, `ideas/later-retry-jitter.md`); vcs-toolkit will
ping when a concrete consumer needs either. Follow-on `ok_codes`/`is_transient()`/
`timeout_grace` adoption tracked in vcs-toolkit's `ROADMAP.md`.
