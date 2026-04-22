# Pre-authorize Monitor + ScheduleWakeup via `allowed-tools` — design

**Date:** 2026-04-22
**Issue:** [#9](https://github.com/qubitrenegade/github-pr-review-loop/issues/9)
**Type:** Spec/design doc for a minimal SKILL.md frontmatter + body edit. The implementation PR is a minimal single-file change — two edits, both landing in `skills/github-pr-review-loop/SKILL.md`: a 3-line `allowed-tools` block-sequence addition to the frontmatter + a one-sentence rewrite of "The loop" step 7. No new files, no code.

## Problem

During disciplined Copilot review loops, the `Monitor` tool is materially better than `ScheduleWakeup` for polling: it's event-driven, emits as soon as Copilot posts a new review (~30s reaction latency), and doesn't burn cache on fixed-interval wakeups that miss the actual event. Observed during clickwork 1.0 / PR #109.

The friction: every `Monitor` invocation currently triggers a permission allow-dialog. For a multi-round review loop that's one dialog per round. If the user stepped away expecting the loop to keep iterating, it stalls at the next `Monitor` prompt.

The user's current workaround: manually add `"Monitor"` to `permissions.allow` in `.claude/settings.local.json`. Works immediately, but it's per-project and not baked into the skill, so every new project that installs this skill hits the same friction.

## Design

### Scope

Single-file edit to `skills/github-pr-review-loop/SKILL.md`:

1. **Add an `allowed-tools` frontmatter key** pre-authorizing `Monitor` and `ScheduleWakeup` while the skill is active. The `allowed-tools` field is the documented Claude Code mechanism for skills to pre-authorize tools — invoking a tool listed there does not trigger the permission allow-dialog.
2. **Rewrite "The loop" step 7** to reference `Monitor` as the primary polling mechanism with `ScheduleWakeup` as fallback. Preserves the "never busy-poll" guardrail.

No other files edited. No code. No new references added. No plugin-manifest changes (Claude Code's plugin.json schema does not support permission declarations; that capability was investigated and ruled out during the brainstorm).

**Out of scope:**

- Plugin-level permission declarations (`.claude-plugin/plugin.json`) — Claude Code does not support this today.
- Install-time permission bundling / approval workflows — not supported.
- Broader event-driven tool set: `RemoteTrigger`, `PushNotification`, `TaskStop`. The issue speculatively listed these, but the skill does not currently use them; pre-authorizing them would be surprise scope creep (the user would get tool access they didn't realize the skill came with). If the skill later grows to use these tools, adding them to `allowed-tools` is a tiny additive edit at that time.
- Deep polling-pattern documentation (e.g., a new "Monitor vs ScheduleWakeup" subsection). Monitor's own tool description covers the tradeoffs; duplicating that content in SKILL.md is cheap-to-write but decays as the tool evolves.

### Design choices (locked in during brainstorm)

- **Tool scope: `Monitor` + `ScheduleWakeup`** (the polling pair), not broader event-driven tools. Monitor is the explicit ask in the issue; ScheduleWakeup is already a referenced primitive in the current SKILL.md body, so pre-authorizing it consistently is net-positive — the body already recommends it, the allowlist should match.
- **Body depth: minimal step-7 update**, not a new subsection. One-sentence rewrite makes the discovery pointer clear (Monitor is preferred); users who want the full tradeoff read Monitor's own tool description. A subsection duplicates tool-owned content.
- **No plugin.json edits.** The research agent confirmed that plugin manifests don't support permission declarations today; `allowed-tools` in SKILL.md frontmatter is the only supported path.

### SKILL.md changes

#### 1. Add `allowed-tools` to frontmatter

The current YAML frontmatter has `name`, `description`. Add a third key as an explicit YAML block sequence — the unambiguously-a-list form. This convention is used by other Claude Code skills in the broader ecosystem (examples: external plugins `telegram/skills/access/SKILL.md` and `imessage/skills/configure/SKILL.md`, found in the Claude-Plugins-Official marketplace; not paths in this repository):

```yaml
allowed-tools:
  - Monitor
  - ScheduleWakeup
```

The full frontmatter after the edit:

```yaml
---
name: github-pr-review-loop
description: Drives GitHub PRs through Copilot review to merge via disciplined triage (apply / dismiss / clarify / defer / acknowledge), empirical dismissal of hallucinations, GraphQL-based re-request, and concrete stop conditions. Use for a Copilot-reviewed PR that needs driving to merge, for parallel batches of related PRs, or when deciding whether a Copilot finding is real.
allowed-tools:
  - Monitor
  - ScheduleWakeup
---
```

Rationale for block-list form: an inline comma-separated value (`allowed-tools: Monitor, ScheduleWakeup`) parses as a single YAML scalar string `"Monitor, ScheduleWakeup"`, not a list. The block-sequence form is unambiguously a list at the YAML level — no parser-specific comma-splitting required. Using it keeps the value's intended shape explicit and avoids silent-fail risk if the parser ever tightens its interpretation of the scalar form.

Rationale: `allowed-tools` is the documented Claude Code mechanism for skill-scoped pre-authorization. Invoking `Monitor` or `ScheduleWakeup` while this skill is active will not trigger the per-call allow-dialog. Permission is scoped to the skill's active lifetime; outside the skill, the user's existing allow/deny settings still apply.

#### 2. Rewrite "The loop" step 7

Current step 7 text:

> 7. Wait. Use `ScheduleWakeup` (Claude Code) or a cron / cadence — never busy-poll. 4-5 min is a sensible interval.

New step 7 text:

> 7. Wait. Use `Monitor` (event-driven — emits as soon as Copilot posts a new review, ~30s reaction latency; preferred) or `ScheduleWakeup` (fixed cadence, 4-5 min intervals; fallback when `Monitor` isn't available or when you want cache-aware timing) — never busy-poll.

Both tools are pre-authorized via the frontmatter change above — callers don't need to approve per-call.

### Verification

Docs-only, minimal single-file change (two hunks: a 3-line `allowed-tools` block-sequence addition to the frontmatter + a one-sentence rewrite of step 7):

1. **Frontmatter check** — `head -8 skills/github-pr-review-loop/SKILL.md` shows the new `allowed-tools:` key in correct YAML block-sequence form (the `allowed-tools:` header line followed by `  - Monitor` and `  - ScheduleWakeup` on separate lines, all inside the frontmatter block).
2. **Step-7 check** — grep confirms new text landed and old single-tool wording is gone:

   ```bash
   # New text present (body)
   grep -n "Monitor.*event-driven" skills/github-pr-review-loop/SKILL.md

   # Frontmatter block-list form (three lines total)
   grep -n "^allowed-tools:" skills/github-pr-review-loop/SKILL.md
   grep -n "^  - Monitor$" skills/github-pr-review-loop/SKILL.md
   grep -n "^  - ScheduleWakeup$" skills/github-pr-review-loop/SKILL.md

   # Old single-tool step-7 wording is fully replaced
   grep -c "ScheduleWakeup (Claude Code) or a cron" skills/github-pr-review-loop/SKILL.md
   # expect 0
   ```

3. **Reload test (manual, post-merge)** — start a fresh Claude Code session invoking this skill in a repo where `Monitor` was previously prompting. Confirm `Monitor` no longer triggers the allow-dialog. Not CI-automatable; primary-user post-merge manual check.

4. **Copilot review loop** on the implementation PR itself.

No automated tests — the change is a YAML frontmatter addition plus a single sentence rewrite.

## Out-of-scope / follow-ups

After the full spec → implementation sequence lands (this PR plus the follow-up implementation PR it describes), issue #9 is resolved.

Possible future additions (not blocking):

- If the skill grows to use `RemoteTrigger`, `PushNotification`, or `TaskStop`, add them to `allowed-tools` at that time.
- If Claude Code adds plugin-manifest-level permission declarations, re-evaluate whether this skill benefits from declaring permissions at the plugin level instead of the skill level.
- A deeper polling-pattern subsection (Monitor vs ScheduleWakeup tradeoffs with examples) if users report confusion about when to use which. YAGNI until then.
