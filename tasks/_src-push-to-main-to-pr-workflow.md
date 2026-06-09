# Rewrite "push-to-main" → feature-branch + PR (for branch protection)

A portable recipe for bringing a repo's agent-instruction docs into line with
**branch protection on `main` that requires pull requests**. Apply it to any repo
whose `CLAUDE.md` / `AGENTS.md` still document the old "work lives on `main`,
push straight to `main`" flow.

## When to use

Run this whenever you're about to turn on branch protection (require PRs) for a
repo whose `CLAUDE.md` / `AGENTS.md` were generated from the C# repo template (or
otherwise describe a push-to-main jj workflow).

## Why

- A protection rule that **requires pull requests** rejects any direct push to
  `main` — so docs telling the agent to `jj bookmark set main` + `jj git push
  --bookmark main` are now actively wrong and will fail.
- The global `vcs-workflow` plugin (`vcs-workflow@zelanton-claude-plugins`) already
  pushes to *"the active bookmark's upstream, never `main` by default"* and only
  touches `main` when `main` is the active bookmark — i.e. it already assumes a
  feature-branch model. The per-repo docs are the lagging, conflicting piece; this
  recipe aligns them.
- A release workflow that pushes a **commit** straight to `main` is the one actor that
  still needs to reach `main` under protection, so it needs a bypass. How you phrase
  that exception depends on what the repo's `release.yml` actually does — match it
  (see §2a); do not assume a `RELEASE_TOKEN` exists. **Do not** change `release.yml` —
  only the docs.

## 1. Locate

From the repo root:

```sh
rg -n "push-to-main|bookmark set main|push --bookmark main|Work lives on .?main|No new bookmarks|publish target|default flow is push"
```

Expected sections to fix:

- `CLAUDE.md` — **"Version control workflow"**: the "Sync on the user's trigger"
  handshake (step that does `jj bookmark set main` / `jj git push --bookmark main`)
  and the "No new bookmarks … Work lives on `main`" bullet.
- `AGENTS.md` — **"Pushing to remote"** (steps that move/push the `main` bookmark)
  and the **"Bookmarks"** section.
- `TEMPLATE.md` (template repos only) — the post-setup checklist branch-protection
  bullet.

Adjust section names to whatever the repo actually uses; the wording, not the
heading, is what matters.

## 2. Replace

Drop-in blocks below. `<topic>` = a short kebab-case name for the change/PR;
`main` = the repo's default branch. The jj commands mirror the global plugin's
vocabulary (`jj bookmark move <name> --to @`, `jj git push -b <name>`). The blocks
show the `RELEASE_TOKEN` variant of the release-bot exception — **swap in your repo's
clause from §2a** before pasting.

### 2a. Adapt the release-bot exception first

The `Direct-push fallback` lines and the TEMPLATE.md bullet end with a release-bot
exception clause. **Open the repo's `.github/workflows/release.yml` and match the
wording to what it actually does** — getting this wrong tells you a release is safe
under protection when it isn't:

- **Pushes a commit to `main` with `RELEASE_TOKEN || GITHUB_TOKEN`** (a `RELEASE_TOKEN`
  is wired): *"…except the release bot (its `RELEASE_TOKEN`/bypass)."*
- **Pushes a commit to `main` with only the default `GITHUB_TOKEN`** (no `RELEASE_TOKEN`
  anywhere): *"…except an automated actor you grant a branch-protection bypass — the
  release step pushes to `main` with the default `GITHUB_TOKEN`, so the Actions bot
  needs a bypass entry."* Do **not** invent a `RELEASE_TOKEN`.
- **Pushes tags only (never a commit to `main`)**: requiring PRs does **not** block it —
  drop the exception and instead note *"the release workflow only pushes tags, so
  requiring PRs doesn't block it."*

### CLAUDE.md — "Sync on the user's trigger" handshake

```markdown
- **Sync on the user's trigger.** When the user says `pull` (or `push`/`sync`), run the full handshake:
	1. `jj git fetch` first — picks up any remote movement (merged PRs, CI release commits, etc.).
	2. Rebase if `main@origin` advanced: `jj rebase -r @- -d main@origin` (or `jj rebase -d main@origin` for a stack).
	3. Put the work on a **feature bookmark**, not `main`: `jj bookmark create <topic> -r @` the first time (then `jj bookmark move <topic> --to @` as it grows), and push only it: `jj git push --allow-new -b <topic>`.
	4. Open a pull request into `main` with a **filled-in description** — a real summary of *what changed and why* (not just the commit subject): `gh pr create --base main --head <topic> --title "<summary>" --body "<description>"`. `gh` prints the PR URL.
	5. **Report back to the user**: print the PR description you wrote *and* the PR link, so they can review without opening anything. `main` advances only when that PR merges; afterwards `jj git fetch` brings the merge down and you `jj bookmark delete <topic>`.

	Never push without an explicit signal from the user. **Direct-push fallback:** where `main` is *not* protected, the old flow still works — `jj bookmark move main --to @` then `jj git push -b main`. Once branch protection requires PRs, a direct push to `main` is rejected for everyone except the release bot (its `RELEASE_TOKEN`/bypass).
```

### CLAUDE.md — the "No new bookmarks" bullet

```markdown
- **Feature bookmarks are the unit of work** — one per PR, short kebab-case topic name. Don't advance `main` locally to publish; `main` moves only via merged PRs and the release workflow's tagged commit. (Previously work lived directly on `main`; branch protection requiring PRs makes direct push the exception — see the fallback above.)
```

### AGENTS.md — "Pushing to remote" steps

```markdown
1. `jj git fetch` — pull down remote movement (merged PRs, CI release commits, other contributors) **before** doing anything else.
2. If `main@origin` has moved past the local change, rebase onto it: `jj rebase -r @- -d main@origin` (or `jj rebase -d main@origin` for a stack).
3. Put the work on a **feature bookmark — never advance `main` locally to publish.** First push: `jj bookmark create <topic> -r @` then `jj git push --allow-new -b <topic>`. Later pushes: `jj bookmark move <topic> --to @` then `jj git push -b <topic>`.
4. Open / update a pull request into `main` with a **filled-in description** (a real summary of *what changed and why*, not just the commit subject): `gh pr create --base main --head <topic> --title "<summary>" --body "<description>"`. `gh` prints the PR URL.
5. **Report back to the user**: print the PR description you wrote *and* the PR link, so they can review without opening anything. `main` advances only when the PR merges; afterwards `jj git fetch` and `jj bookmark delete <topic>`.

Never push without an explicit signal from the user. **Direct-push fallback:** where `main` is unprotected the old single-step flow still works — `jj bookmark move main --to @` then `jj git push -b main`; once PRs are required this is rejected for everyone except the release bot (`RELEASE_TOKEN`/bypass).
```

### AGENTS.md — "Bookmarks" section

```markdown
### Bookmarks

Work is published through a **feature bookmark per PR** (short kebab-case topic name), merged into `main` via pull request — this keeps the flow compatible with branch protection on `main`. Create the bookmark when you're ready to push for review; `main` is never advanced locally to publish (it moves only via merged PRs and the release workflow's tagged commit). Where `main` is unprotected, a direct push to `main` stays a valid shortcut — see "Pushing to remote".
```

### TEMPLATE.md — post-setup checklist bullet (template repos only)

```markdown
- [ ] Branch protection for `main` configured — require pull requests (plus CI / CodeQL
      status checks). The agent docs (`CLAUDE.md` / `AGENTS.md`) already assume a
      feature-branch + PR flow into `main`. Requiring PRs blocks the release workflow's
      direct push of the release commit — give the release actor a bypass or add a
      `RELEASE_TOKEN` secret (see the note in `.github/workflows/release.yml`).
```

> **Indentation:** these blocks use **tabs** (matching a template generated with a
> tabs `.editorconfig`). If the target repo indents Markdown with spaces, convert
> the leading tabs to spaces before pasting.

## 3. Leave alone

- **`.github/workflows/release.yml`** — leave it unchanged regardless of which token it
  uses (`RELEASE_TOKEN`, plain `GITHUB_TOKEN`, or tags-only). Its push behaviour is
  intended; here you only *document* the bypass, you don't rewire the workflow.
- **`CONTRIBUTING.md` / PR template** — usually already PR-oriented; only touch if
  they still describe pushing to `main`.

## 4. Verify

```sh
# No stale push-to-main language survives (hits should only be the new
# "direct-push fallback" / historical-note phrasing):
rg -n "bookmark set main|push --bookmark main|Work lives on .?main|No new bookmarks|default flow is push" CLAUDE.md AGENTS.md TEMPLATE.md

# PR flow is now present in both agent docs:
rg -n "feature bookmark|pull request|gh pr create|--allow-new" CLAUDE.md AGENTS.md

# release.yml untouched. (RELEASE_TOKEN only appears if the repo wires it — repos
# that push with the default GITHUB_TOKEN or tags-only won't match, which is expected.)
rg -n "RELEASE_TOKEN" TEMPLATE.md .github/workflows/release.yml
```

## 5. GitHub setup (out of band)

After the docs are updated, in **Settings → Branches** add a rule for `main`:
require a pull request before merging (and the CI / CodeQL status checks you want).
If the repo's `release.yml` pushes a **commit** to `main` (see §2a), give its actor a
bypass — for a `GITHUB_TOKEN` release that's the `github-actions` bot; or add a
`RELEASE_TOKEN` PAT/App token with bypass. A tags-only release needs no bypass.
