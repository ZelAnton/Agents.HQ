# Release under branch protection: push with a GitHub App token

A portable recipe for any repo whose `release.yml` **pushes a commit to `main`**
(version bump + changelog) and whose `main` is (about to be) protected by a ruleset
that blocks direct pushes.

## The problem

Under a ruleset that requires PRs / blocks non-fast-forward pushes to `main`, the
release workflow's `git push … HEAD:refs/heads/main` is rejected. The obvious fix —
"add `github-actions[bot]` to the ruleset bypass list" — **is not possible**:
`github-actions[bot]` (the actor behind the default `GITHUB_TOKEN`) is a **system
actor, not a GitHub App**, so it does not appear in the ruleset's *Add bypass* picker
(you'll only see Roles, Deploy keys, and installed Apps). This is deliberate — it
stops a compromised workflow file from bypassing protection.

## The fix — a dedicated GitHub App (recommended)

Push as a **GitHub App** instead of the bot. Apps *do* appear in the ruleset *Add
bypass* picker, the App's installation token is **short-lived (≈1 h) and auto-revoked**
(nothing to rotate, unlike a PAT), and it gives a clean, app-scoped audit trail.

### One-time GitHub setup

1. **Create the App** — your account → Settings → Developer settings → **GitHub Apps →
   New GitHub App**. Minimum config:
   - **Repository permissions → Contents: Read and write** (Metadata: Read-only is
     required automatically). Nothing else.
   - **Webhook → Active: off** (uncheck — no webhook needed).
   - "Where can this be installed": *Only on this account*.
2. **Generate a private key** for the App (its settings page → *Private keys → Generate*)
   and download the `.pem`. Note the **App ID** — the number labelled **"App ID"** at the
   top of the App's *settings* page.
   > ⚠️ **App ID, not Installation ID.** They look alike (both small integers) and are
   > easy to swap. The **Installation ID** is the number in the install URL
   > (`…/settings/installations/<installation-id>`) — `create-github-app-token` rejects
   > it. Cross-check: it must equal the `actor_id` GitHub stores when you add the App to
   > the ruleset bypass (step 4) — `gh api repos/<owner>/<repo>/rulesets/<id> --jq
   > '.bypass_actors[] | select(.actor_type=="Integration").actor_id'`.
3. **Install the App** on the repo (App settings → *Install App* → pick the repo).
4. **Add the App to the ruleset bypass** — repo → Settings → Rules → your ruleset →
   *Bypass list → Add bypass* → the App now appears under **Apps** → select it.

### Per-repo wiring

5. Add a repo **variable** `RELEASE_APP_ID` = the App ID, and a repo **secret**
   `RELEASE_APP_PRIVATE_KEY` = the full contents of the `.pem`
   (Settings → Secrets and variables → Actions → *Variables* / *Secrets*).
6. In `release.yml`, mint a token before checkout and push with it:
   ```yaml
   - name: Mint GitHub App token
     id: app-token
     if: ${{ vars.RELEASE_APP_ID != '' }}      # skip → falls back to GITHUB_TOKEN
     uses: actions/create-github-app-token@v2
     with:
       app-id: ${{ vars.RELEASE_APP_ID }}
       private-key: ${{ secrets.RELEASE_APP_PRIVATE_KEY }}

   - uses: actions/checkout@v5
     with:
       ref: main
       fetch-depth: 0
       # checkout persists this token, so the later `git push` to main uses it →
       # the App's ruleset bypass applies. Empty when the App isn't configured.
       token: ${{ steps.app-token.outputs.token || secrets.GITHUB_TOKEN }}
   ```
   > `@v2` still ships on Node 20 (being force-migrated to Node 24 mid-2026); it runs
   > fine for now. Bump to `actions/create-github-app-token@v3` once it leaves beta.
   The `|| secrets.GITHUB_TOKEN` fallback keeps the workflow working before the App
   exists / before `main` is protected.
7. **(Recommended) Attribute the release commit to a human**, so it reads as authored
   by the maintainer (and counts toward their history) rather than the App. Author
   identity is independent of the push token — set it in the commit step:
   ```yaml
   git config user.name  "Your Name"
   git config user.email "your-github-email"   # an email verified on your GitHub account
   ```
8. Done. Trigger a release: the bump commit lands on protected `main` (pushed by the
   App via its bypass), authored by the maintainer; the tag + GitHub Release follow.

## Alternatives

- **Personal Access Token (PAT)** — simpler, no App to create. A fine-grained PAT
  (Contents: read/write) acts as its **owner**; if the owner is a repo admin and the
  **Repository admin** role is in the ruleset bypass (default), the push goes through —
  no new bypass entry needed. Store it as secret `RELEASE_TOKEN` and use
  `token: ${{ secrets.RELEASE_TOKEN || secrets.GITHUB_TOKEN }}` on checkout. Downside:
  PATs **expire** and need rotation; the App avoids that.
- **Deploy key** — can be added to the bypass list, but pushes have no human author
  attribution. Usually worse than the App or a PAT.

## Applies to

All repos in this family with the **commit-to-main** `release.yml` (Rust *and* .NET —
same `actions/checkout` shape): `ProcessKit-rs`, `vcs-toolkit-rs`, `vcs-flow-rs`,
`agent-workspace`, `ghRun`, `jjRun`, `ConsoleKit`, `ProcessGroup`, `vcs-toolkit-dotNet`,
`ProcessKit`. One App can be installed on all of them; each repo just needs its own
`RELEASE_APP_ID` variable + `RELEASE_APP_PRIVATE_KEY` secret and the two workflow edits.

## Verify

After the first protected release: the `Release vX` commit is on `main`, authored by
the maintainer (not `github-actions[bot]`), the `vX` tag + GitHub Release exist, and the
Actions log shows no "protected branch" / "required status check" rejection.

## See also

`rewrite-push-to-main-to-pr-workflow.md` — §2a (release-bot exception wording) and §5
(GitHub branch-protection setup). This doc is the concrete "let the release push reach a
protected `main`" half of that exception.
