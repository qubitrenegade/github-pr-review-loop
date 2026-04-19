# Case study — clickwork 1.0.0

Concrete run of this skill's pattern on a real repo: shipping
[clickwork 1.0.0](https://pypi.org/project/clickwork/) — 24 issues
closed across ~25 PRs (roadmap + per-wave plans + 23 implementation
PRs + release cut + polish follow-ups) in ~20 hours. Useful as ground
truth when deciding whether this skill's generalisation applies to
your situation.

## Contents

- Session at a glance
- Roadmap + wave structure
- Wave-by-wave breakdown
- The mistakes that got caught
- Transcript excerpts — real Copilot findings + replies
- What did not work

## Session at a glance

- **Repo:** qubitrenegade/clickwork (Python CLI framework)
- **Starting state:** 0.2.0 on PyPI, 24 issues in scope (#35-#60)
- **Target:** ship 1.0.0 to PyPI same day, update downstream
  consumer (orbit-admin) to 1.0
- **Final state:** 1.0.0 live on PyPI, signed `v1.0.0` tag, orbit-admin
  merged to `clickwork>=1.0,<2`, three follow-ups left open on purpose
  for future cycles (#61 Sigstore attestations + workflow-driven tag
  signing for 1.0.x, #62 conda-forge recipe for post-1.0, #94 mkdocs
  docs site)
- **Total PRs:** ~25 in clickwork (roadmap + wave plans + issue PRs +
  release cut + post-release polish), 1 in orbit-admin
- **Copilot rounds total:** ~70 across all PRs
- **Time:** ~20 hours wall clock, overlapped across waves

## Roadmap + wave structure

Session started with a roadmap PR ([#63](https://github.com/qubitrenegade/clickwork/pull/63))
that pinned:

- 4 waves, each scoped to a coherent theme (packaging, features,
  polish, docs)
- Release cut target (single-PR bump of version + CHANGELOG after
  all waves merge)
- Parallelism policy **B** (overlap wave N+1 prep during wave N's
  Copilot bake time)

Waves landed as:

| Wave | Theme | Issues | PRs |
|---|---|---|---|
| 1 | Package metadata + API policy | #35, #36, #46, #49 | #64, #65 |
| 2 | Features + infra | #37-#43, #47-#48, #57, #59 | #66-#77 (12 PRs) |
| 3 | Feature completion | #50-#52, #60 (part b — `add_global_option` override) | #78-#81 |
| 4 | Docs | #53-#56, #58 (the #54 config-precedence doc landed here after #80 fail-fast merged) | #82-#86 |
| 5 | Release cut + polish | version bump | #87 + follow-ups |

Wave 2 had 12 PRs. The parallelism policy was the single biggest
throughput lever — without it, 12 serial review loops would have taken
8+ hours; with overlapped bake time, Wave 2 finished in ~3 hours.

## Wave-by-wave breakdown

### Wave 1 (packaging)

- PRs: #64 (package metadata), #65 (API policy)
- Sequential (#64 must land before #65 can reference the published
  API surface)
- Low findings count per PR — mostly trove classifier nits, link
  checks, wording

### Wave 2 (features + infra, 12 PRs)

- Dispatched as full parallel (policy B with wave 1 merged first)
- One worktree per PR under `clickwork.worktrees/<name>-<issue>`
- Scheduled wake-ups at 4-5 min intervals, staggered by 30s across
  PRs so all 12 reviews didn't fire simultaneously
- Several PRs needed 4-6 Copilot rounds. One needed 7 when a
  conftest monkeypatch signature drift surfaced late.
- Wave merged in ~3 hours with no cross-PR conflicts.

### Wave 3 (feature completion)

- 4 PRs, mostly overlapping with wave 2's late review rounds
- Wave 3's #80 introduced a fail-fast behavior (`ConfigError` on
  undefined `env`). Two other PRs in wave 3 (#79 mixed-discovery
  tests, #81 `add_global_option` semantics) had merge-order
  dependencies on #80's error shape.
- Resolved by explicit merge-ordering in the wave plan.

### Wave 4 (docs)

- 5 docs PRs (MIGRATING, PLUGINS, SECURITY, CONTRIBUTING, GUIDE
  config precedence)
- Much higher review volume per PR because docs expose hallucinations
  (Copilot sometimes says "this link is broken" when it isn't — the
  evidence-based dismissal pattern closes these fast)
- Case study fixture for `triage-patterns.md` examples

### Release cut

- Version bump PR (#87): pyproject 0.2.0 → 1.0.0, CHANGELOG 1.0.0
  entry, trove classifier Beta → Production/Stable
- Signed tag pushed by the human maintainer with `git tag -s v1.0.0`
  after `export GPG_TTY=$(tty)` (captured in the release runbook PR
  #93)
- Tag-push triggered `publish.yml` which was itself rewritten mid-
  session in PR #90 to do build + create-release + PyPI publish in
  one flow (the original `on: release.published` trigger required a
  manual `gh release create` step, which broke the "push the tag =
  release" expectation)

## The mistakes that got caught

Three real mistakes happened during this session. All got caught by
the loop discipline — worth studying because they show failure modes
the skill explicitly warns against.

### 1. Admin-merging over failing CI

**What happened.** Several wave 2 PRs showed the Release smoke job
failing, and the main branch ALSO showed it failing. The agent
rationalised "same failure on main = pre-existing infra, not a
blocker" and used `gh pr merge --admin` to merge the PRs.

**What was wrong.** The Release smoke job was failing for a real
reason (the workflow used `uv venv` which doesn't install pip, but
then called `/tmp/wheel-smoke/bin/pip install`). The workflow was
broken. Merging past it didn't fix anything; it just added more PRs
whose release-smoke signal was untrusted.

**What fixed it.** Maintainer caught it. PR #88 rewrote the smoke
workflow to use `uv pip install --python` instead of the pip-less
venv's pip. After #88 merged, Release smoke went green across all
subsequent PRs and the signal was trustworthy again.

**Lesson.** Don't admin-merge over failing CI, even if the same
failure appears on main. "Infra is broken" is a reason to fix the
infra, not a reason to ignore the gate. Captured in the skill's
"What to never do" list.

### 2. Wrong branch parent

**What happened.** After merging a few PRs, the agent opened PR #90
from a branch that had been created from `release/1.0.0` (which
squash-merged into main) instead of `main`. The PR diff showed 6
files changed when only 1 was intended, because git couldn't tell
the already-squashed commits were redundant with the current main.

**What fixed it.** `git rebase --onto origin/main release/1.0.0
<branch>` cleaned up the diff to just the intended file.

**Lesson.** When merging squash-style, cleanly delete the merged
branches locally before starting new work. Branch off `origin/main`
explicitly every time: `git checkout -b <new> origin/main`. The skill's
wave-orchestration reference covers this as worktree-per-PR discipline.

### 3. Wrong release trigger

**What happened.** `publish.yml` triggered on `release.published`,
which meant pushing the `v1.0.0` tag didn't actually ship anything
— the agent had to follow up with `gh release create` to fire the
workflow.

**What was wrong.** The maintainer had expected "push the tag =
release" from the start (matches the pattern in the sibling
orbit-widener repo's `release.yml`). The trigger mismatch was not
the agent's mistake (the workflow predated the session), but the
agent hadn't noticed + flagged it before the 0.2.0 cut, and only
surfaced it mid-1.0 work when the maintainer asked why the tag
push did nothing.

**What fixed it.** PR #90 rewrote `publish.yml` to `on: push: tags:
['v*']` with a 3-stage flow matching orbit-widener's pattern: build
→ create release (via `softprops/action-gh-release@v2`) → PyPI
publish.

**Lesson.** Check the release trigger early. "It worked last time"
is not a guarantee it worked the way the maintainer expected.

## Transcript excerpts — real Copilot findings

Sample Copilot findings and the replies that closed them, pulled from
the clickwork 1.0 PRs. Shows the triage patterns in context.

### Apply (Copilot right, fix + SHA)

> **Copilot on PR #87, line 3:** `version` is bumped to 1.0.0 here,
> but the runtime version constant is still `__version__ = "0.2.0"`
> in `src/clickwork/__init__.py`, which will make
> `clickwork.__version__` (and any `--version` functionality that
> relies on it) report the stale value.

Reply:

> Fixed in `bb56bfc` — bumped `__version__` to 1.0.0 in
> src/clickwork/__init__.py. Good catch, this would have broken any
> consumer's `--version` resolution.

Later refined to `importlib.metadata.version("clickwork")` in
commit `3ca869a` so the two can't drift again.

### Dismiss (Copilot wrong, evidence dismissal)

> **Copilot on PR #83, line 238:** The cross-reference link to
> `LLM_REFERENCE.md#common-footguns` appears to be broken:
> `docs/LLM_REFERENCE.md` currently has no matching section/anchor.

Reply after verifying:

> Dismissing (hallucination): `docs/LLM_REFERENCE.md` line 184 has
> `## Common Footguns` which renders as anchor `#common-footguns`
> under GitHub-flavored Markdown. The link resolves.

Evidence command used: `grep -nE '^## Common' docs/LLM_REFERENCE.md`
— returned the heading, confirmed the anchor.

### Apply (subtle accuracy issue)

> **Copilot on PR #89, line 133:** The new re-invocation paragraph
> says `setup_logging()` finds any existing `_clickwork_owned`
> handler and reuses it in place. That's not always true: when
> `_host_root_is_configured()` is true, the implementation
> explicitly REMOVES the clickwork-owned handler.

Reply:

> Fixed in `9bf4cfd` — split the re-invocation paragraph into two
> explicit bullets: standalone CLI mode reuses the `_clickwork_owned`
> stream handler in place; host-configured mode actively
> `removeHandler()`-s it so records only flow through the host's
> root. Also added
> `test_reinvocation_evicts_stream_handler_when_host_configures_after`
> pinning the specific transition path you flagged.

This was the kind of catch that's hard without a reviewer who reads
the code carefully — substantively correct, subtle, and would have
shipped a doc that was accurate-in-one-mode, wrong-in-the-other.

### Copilot repeats itself

On PR #82, Copilot raised "docs/LLM_REFERENCE.md#common-footguns is
broken" in round 2, got dismissed with the same `grep` evidence as
PR #83, then raised the same finding again in round 3.

Round-3 reply:

> Same as addressed in round 2 (see thread above). `grep -nE
> '^## Common' docs/LLM_REFERENCE.md` returns line 184; anchor is
> valid. Not changing the link.

No code change. PR merged.

## What did not work

Not everything in the session's first attempt stuck.

- **Initial stop condition of "2 clean rounds"** — replaced with "1
  clean round" after observing that the second round almost always
  returned empty and the wait was pure cost. Now the recommendation
  in this skill.
- **Planning Sigstore for 1.0.0** — descoped to 1.0.1 (tracked in
  #61) when it became clear the workflow-driven signing setup was
  its own multi-PR mini-cycle.
- **Attempting to `--admin` past Release smoke failures.** Got
  caught, led to PR #88 (fix the actual workflow).
- **Forgot `GPG_TTY=$(tty)` on the first `git tag -s` attempt.**
  The first tag sign failed with `Inappropriate ioctl for device`
  because pinentry couldn't find a TTY. Now documented in
  CONTRIBUTING.md and in the skill's troubleshooting section.

The session landed 1.0.0 anyway because the loop discipline caught
most of these before they caused lasting damage, and the maintainer
caught the rest in time.
