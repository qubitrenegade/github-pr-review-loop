# github-pr-review-loop

A Claude Code skill for running a disciplined GitHub PR review loop: triage
every reviewer comment into **apply / dismiss / clarify**, dismiss
hallucinations with empirical evidence, and stop chasing rounds when Copilot
starts repeating itself. Scales from one PR to many with parallel worktrees.

This skill encodes the habits from shipping [clickwork
1.0.0](https://pypi.org/project/clickwork/) (24 issues, 19 PRs, 1 day of
parallel waves), generalised so it applies to any repo with GitHub Copilot
PR reviewer turned on.

## When Claude should invoke this skill

- You've opened a PR and want the agent to drive it through Copilot review
  to merge, handling each finding correctly instead of thrashing on every
  suggestion.
- You're tackling a batch of related issues across many PRs and want to
  orchestrate parallel loops without cross-wave conflicts.
- You need to decide whether a Copilot comment is real or a hallucination,
  and you want evidence-backed dismissal rather than guessing.

## What the skill teaches

- **Triage by category.** Every review finding is one of three things:
  apply, dismiss, or clarify. Each has a template and a commit-SHA reply
  convention so the review thread stays navigable.
- **Empirical dismissal.** Copilot hallucinates. Before taking its word,
  `grep -c`, `python -c`, or a test run is cheap. The skill prescribes this
  check on every "this looks broken" claim.
- **Correct re-request mechanics.** The only way to re-trigger a Copilot
  review is the `requestReviews(botIds: [...])` GraphQL mutation after you
  push fixes. `@-mentioning` the reviewer in a comment does nothing. The
  skill encodes the exact call.
- **Stop conditions that aren't arbitrary.** One clean Copilot pass (zero
  new findings) is the real signal, not some arbitrary "round 4 threshold".
  The skill lists the signals and an escape hatch.
- **Wave orchestration at scale.** For multi-PR rollouts: parallelism
  policy, worktree-per-PR discipline, scheduled wake-ups instead of
  busy-waiting, overlap prep with Copilot bake time.

## Install

### As a plugin

```bash
/plugin install https://github.com/qubitrenegade/github-pr-review-loop
```

### Manual

Copy `skills/github-pr-review-loop/` into your Claude config:

```bash
# Personal (applies to every project)
cp -r skills/github-pr-review-loop ~/.claude/skills/

# Or project-local (applies only to the current repo)
cp -r skills/github-pr-review-loop .claude/skills/
```

Restart your Claude Code session (or start a new one) and the skill's
metadata is loaded; the full prompt loads when Claude decides the task
matches.

## Requirements

- `gh` CLI installed and authenticated for the repo you're reviewing in
- GitHub Copilot PR reviewer enabled on the repo (free for public repos, a
  subscription item for private)
- The repo must allow bot review requests (default in GitHub settings;
  some orgs restrict this)

## Scope

**GitHub-specific.** Copilot PR reviewer is a GitHub feature. The GraphQL
`requestReviews` mutation is GitHub API. `gh api` is a GitHub CLI. This
skill is not tested against GitLab Duo or similar; the triage discipline
would port, but the mechanics would need a rewrite.

**Not included:**
- Automated implementation of the fixes Copilot suggests (that's your
  regular development skill set).
- CI setup. The skill assumes working CI on the repo.
- Release cutting. This is about getting PRs to merge cleanly, not about
  tagging + PyPI publishing.

## Structure

```
skills/
└── github-pr-review-loop/
    ├── SKILL.md                            # Core prompt (loaded when invoked)
    └── references/
        ├── triage-patterns.md              # apply / dismiss / clarify templates
        ├── graphql-snippets.md             # requestReviews + comment queries
        ├── stop-conditions.md              # when to stop chasing
        ├── wave-orchestration.md           # multi-PR parallel scaling
        └── case-study-clickwork-1.0.md     # concrete 24-issue run
```

References load on demand, so the active context stays small even when
you're deep in a round-5 review loop.

## Contributing

This is v0.1. The discipline captured here is what worked for one
maintainer on one project. If you use it on a different repo / different
review tool / different scale and find something that needs refining, open
an issue or a PR. Real-usage feedback is better than speculation.

## License

MIT. See [LICENSE](LICENSE).
