# Wave orchestration — running many review loops in parallel

For multi-PR rollouts (closing a batch of related issues in one
session), the single-PR loop runs in parallel across N PRs.

## Contents

- When waves make sense
- The pattern
- Roadmap PR first
- Per-wave plan PR
- Worktree-per-PR discipline
- Parallelism policy — overlap the bake time
- Scheduled wake-ups — never busy-poll
- Merge-ordering constraints
- Cross-PR failure modes
- The "prep during bake" playbook

## When waves make sense

Use waves when:

- The issues are independent enough that they can be worked in
  parallel without blocking each other (branch A doesn't reference
  branch B's unshipped API).
- The total volume is large enough that a single serial thread would
  keep a reviewer waiting hours. Rule of thumb: **more than 5 PRs**
  in a session.
- The maintainer is available during the session to merge, approve
  the release gate, and answer clarifications.

Use sequential when:

- PRs have explicit ordering constraints (A must land before B
  because B documents an API A introduces).
- You're the only human reviewer and can't effectively watch many
  simultaneous threads.
- The repo has strict CI concurrency limits that would serialise
  parallel runs anyway.

## The pattern

```
Brainstorm roadmap PR → merge
  ↓
Wave N:
  - Per-wave plan PR (API shapes, branch names, TDD targets) → merge
  - Prep worktrees for the wave
  - Dispatch subagents (one per issue) with locked briefs
  - Review agent diffs in main session
  - Commit / push / open PRs
  - For each PR in parallel: run the single-PR review loop
  - Stagger wake-ups so they don't all fire at once
  - During Copilot bake time: prep the NEXT wave's worktrees
  - Merge as each PR hits a stop condition
  ↓
Wave N+1 (repeat)
  ↓
Release cut
```

Every layer is a PR of its own. The roadmap is a PR. Each wave plan is
a PR. Each issue is a PR. Review at every layer.

## Roadmap PR first

Before touching any feature code, write a roadmap PR that pins:

- Wave structure (which issues go in which wave and why)
- Parallelism policy for this session (sequential, fully parallel,
  overlap-bake-time)
- Release target (ship 1.0.0 today? 2.0-rc next week?)
- Any cross-cutting decisions that will constrain the waves

The roadmap becomes the reference doc. Plans and implementations cite
it. When in doubt mid-session, re-read the roadmap rather than improvising.

## Per-wave plan PR

Each wave gets its own plan PR before any wave work starts. The plan
answers:

- Which issues does this wave close?
- For each issue, what's the API shape or interface? Lock this in
  before dispatching subagents, because pivots mid-wave are expensive.
- Branch name per issue (conventional: `<type>/<short-desc>-<issue-num>`).
- TDD target per issue (red-test exists and fails; what's green?).
- Any wave-internal merge-order constraints.
- **Size check.** If an issue's scope looks like it will produce a
  PR over ~300 lines of diff or touching more than 3-4 non-test
  files, split it now. Smaller PRs get higher-signal Copilot
  reviews, converge in fewer rounds, and bisect cheaply. This is
  the last opportunity to split cheaply; once code is landing the
  only escape is Defer.

Review + merge this plan before opening any implementation PR from the
wave.

### Brainstorming the plan

The per-wave plan is where the maintainer answers A/B/C questions
on API shape, error ergonomics, deprecation runway, etc. If you
have the `superpowers:brainstorming` skill installed, invoke it
before writing the plan PR — it's built for exactly this kind of
up-front design conversation and produces the kind of "here are
the three options, here's what I picked, here's why" artifact that
the plan PR should contain. This skill (github-pr-review-loop)
then drives the plan PR through its own review loop and any
resulting implementation PRs through theirs.

## Worktree-per-PR discipline

Each PR gets its own worktree, branched from current main (or from
the previous wave's merged state). This isolates concurrent edits.

Run these from the **parent directory** of the repo (one level above
`<repo>/`), so the worktree resolves as a **sibling** of the main
checkout, not nested inside it:

```bash
# cwd: parent dir containing <repo>/
git -C <repo> fetch origin
git -C <repo> worktree add ../<repo>.worktrees/<branch-name> -b <branch-name> origin/main
cd <repo>.worktrees/<branch-name>
# subagent works here
```

Standard worktree root: `<repo>.worktrees/<branch-name>` at the same
level as `<repo>/`. If you run `cd <repo>` first, the path resolves
to `<repo>/<repo>.worktrees/<branch>` — nested inside the main
checkout — which defeats the isolation and makes cleanup fragile.

Clean up after merge (again, from the parent dir):

```bash
# cwd: parent dir
git -C <repo> worktree remove ../<repo>.worktrees/<branch-name>
git -C <repo> branch -d <branch-name>
```

Without worktree-per-PR, a subagent editing branch B while another is
editing branch A in the same checkout causes file-state confusion.

## Parallelism policy — overlap the bake time

Copilot takes 30-90s to start a new review and 1-3 min to complete one.
For N PRs, that bake time is where the win is.

Policy **B** (recommended): while the current wave's PRs are in their
review loops, use the bake time to prep the NEXT wave's worktrees,
dispatch its subagents, and stage commits. By the time wave N's PRs
merge, wave N+1 is already mid-flight.

Policy **A** (sequential): finish wave N fully before starting wave
N+1. Simpler to reason about; slower overall. Use when cross-wave
dependencies are high.

Policy **C** (fully parallel): start every wave at once. Don't. The
cross-wave merge conflicts and concurrent-dispatch cognitive load
aren't worth it outside of toy examples.

## Scheduled wake-ups — never busy-poll

Don't sit in a loop polling PR status every 30 seconds. Schedule a
wake-up, do other work, come back when signaled.

In Claude Code: `ScheduleWakeup` tool with a
`<<autonomous-loop-dynamic>>` payload at 4-5 minute intervals for
single-PR loops, 2-3 minutes for multi-PR orchestration.
(`<<autonomous-loop-dynamic>>` is the dynamic-pacing sentinel
specific to `ScheduleWakeup`; `<<autonomous-loop>>` without the
`-dynamic` suffix is a different sentinel for CronCreate-mode
autonomous loops and is NOT interchangeable — using the wrong one
fails silently and the loop won't resume.)

Stagger wake-ups across PRs so they don't all fire simultaneously:

- PR A: wake in 4 min
- PR B: wake in 5 min (offset by 1 min from A)
- PR C: wake in 6 min
- etc.

When each wake-up fires: check PR status, triage new findings, maybe
push + re-request, schedule the next wake-up.

## Merge-ordering constraints

Sometimes PR B's content references an API named in PR A that hasn't
shipped yet. Two options:

**Option 1: explicit merge order.** Document in the wave plan that B
can't merge before A. Enforce by keeping B in draft until A merges,
then rebasing B.

**Option 2: don't name the API in B until it exists.** Rephrase B to
describe the capability without citing the name. Once A merges, open
a small follow-up PR that adds the name to B's content.

Option 2 is safer for multi-day rollouts — draft PRs can become stale,
or be merged accidentally. Option 1 is fine for same-session rollouts
where the human maintainer is paying attention.

## Cross-PR failure modes

**A fix in PR A needs a reciprocal fix in PR B.** Happens when an
issue is "discovered" mid-wave that touches multiple WIP PRs. Don't
retrofit silently — open a dedicated follow-up PR C that makes the
fix as a single atomic change, and reference it from A and B.

**Rebase cascades.** If PR A lands and PR B was branched from pre-A
main, B needs a rebase. Do this eagerly — don't let a pile of PRs
accumulate rebase debt. `git merge origin/main --no-edit` on the
worktree branch is usually cleaner than `git rebase` for multi-commit
branches under active review.

**Copilot context does NOT bleed across PRs** (each PR gets a fresh
reviewer context), **but the maintainer's context does.** Keep PR
titles and descriptions self-contained so a human reviewer flipping
between 5 tabs doesn't have to reconstruct which PR does what.

## The "prep during bake" playbook

When wave 1 is in review and you're waiting on Copilot:

1. Open wave 2's plan PR if not already merged.
2. Pre-create worktrees for wave 2's issues.
3. Dispatch the first 1-2 subagents for wave 2. They run concurrently
   with wave 1's review loops.
4. When wave 1's scheduled wake-ups fire, merge each PR that's hit a
   stop condition.
5. Once all of wave 1 is merged, the wave 2 subagents should be
   producing diffs. Review, commit, open PRs, start wave 2's loops.

Net effect: wave 2 "starts" as soon as wave 1 enters its review loop,
not after wave 1 merges. Roughly 30-40% faster than sequential for
large batches.
