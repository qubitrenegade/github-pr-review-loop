# Stop conditions

When to stop chasing a Copilot review loop, and the merge gate that
still has to clear before you actually merge. Concrete signals, not
arbitrary thresholds.

## Contents

- Merge precondition: required CI checks are green
- Primary stop: zero new findings on a Copilot pass
- Complement: zero unresolved conversation threads
- Secondary stop: Copilot repeats itself
- Tertiary stop: suggestion volume dries up
- User escape hatch
- Failure-mode stops
- Anti-patterns (don't stop for these reasons)
- Putting it together

## Merge precondition: required CI checks are green

Before any stop condition becomes a merge decision, **every required
CI check on the PR head must be in a green conclusion.** Per GitHub's
required-check docs, the green set is **SUCCESS, SKIPPED, and
NEUTRAL** (GitHub treats NEUTRAL as success for required-check
gating and for dependent-check evaluation). Anything else — FAILURE,
CANCELLED, TIMED_OUT, ACTION_REQUIRED, STARTUP_FAILURE, or still
in-progress — blocks merge. A clean Copilot pass on red CI is not a
merge — it's permission to stop chasing review comments while the
CI problem still needs solving.

Use a whitelist (SUCCESS, SKIPPED, NEUTRAL are the green
conclusions), not a blacklist (FAILURE alone misses CANCELLED,
TIMED_OUT, etc. and falsely green-lights a broken gate).

```bash
gh pr view <N> --repo <owner>/<repo> --json statusCheckRollup --jq \
  '{
    blocking: [.statusCheckRollup[]? | select(.status == "COMPLETED" and .conclusion != "SUCCESS" and .conclusion != "SKIPPED" and .conclusion != "NEUTRAL") | {name, conclusion}],
    pending: [.statusCheckRollup[]? | select(.status != "COMPLETED") | .name],
    green: ([.statusCheckRollup[]? | select(.status == "COMPLETED" and (.conclusion == "SUCCESS" or .conclusion == "SKIPPED" or .conclusion == "NEUTRAL"))] | length)
  }'
```

**Interpret:**

- `blocking == [] && pending == []` → every completed check is
  SUCCESS, SKIPPED, or NEUTRAL → CI gate is clear (matches GitHub's
  own merge gate).
- `blocking != []` → investigate by conclusion. FAILURE means the
  code or workflow is broken — if the failure reproduces on `main`
  unchanged it's pre-existing infra (fix it in a dedicated PR, DO
  NOT admin-merge past). CANCELLED / TIMED_OUT / STARTUP_FAILURE
  usually means re-run. ACTION_REQUIRED usually means a
  first-time-contributor approval or a secret-access prompt.
- `pending != []` → wait. Don't merge mid-CI. Schedule another
  wake-up.

See [case-study-clickwork-1.0.md](case-study-clickwork-1.0.md) for
the Release-smoke episode — concrete example of "failure reproduces
on main → fix the infra first, don't bypass".

## Primary stop: zero new findings

**The most reliable signal.** Copilot completed a review pass on the
latest head and produced no new inline comments. Any existing threads
are replies-to-previously-addressed findings, not fresh signal.

Check empirically by filtering comments on their
`pull_request_review_id`, not on a timestamp comparison. Review-
comment `created_at` can precede the parent review's `submitted_at`
by a second or two (comments exist during composition; the review
is finalised last) — timestamp filters silently miss those and read
as false "clean" passes.

```bash
REPO=<owner>/<repo>
PR_NUM=<N>

# Get the latest Copilot review's ID AND submitted_at in one fetch.
# The REST reviews endpoint exposes Copilot's login as
# "copilot-pull-request-reviewer[bot]" (with the [bot] suffix) —
# which differs from the REST comments "Copilot" and the GraphQL
# "copilot-pull-request-reviewer". See graphql-snippets.md gotcha
# table.
#
# `read` with a tab separator keeps both fields in scope for the
# cross-check further down without requiring a second API call.
read -r LAST_COPILOT_REVIEW_ID LAST_COPILOT_REVIEW_AT < <(
  # `last? | select(.)` short-circuits on an empty filtered array so the
  # jq pipeline emits nothing (not the literal string "null") when Copilot
  # hasn't reviewed yet. Without the guard, `"\(.id)\t\(.submitted_at)"`
  # would interpolate null into a string, bypassing the -z check below.
  gh api --paginate "repos/$REPO/pulls/$PR_NUM/reviews?per_page=100" --jq \
    '[.[] | select(.user.login=="copilot-pull-request-reviewer[bot]")] | last? | select(.) | "\(.id)\t\(.submitted_at)"'
)

# Guard: if Copilot has never reviewed this PR, both fields are empty.
# That is not a "clean pass" — it just means the reviewer hasn't
# run yet. Fall back to an explicit "no reviews" signal so the rest
# of the loop doesn't treat missing data as success.
if [ -z "$LAST_COPILOT_REVIEW_ID" ]; then
  echo "No Copilot review yet — request one (or wait)." >&2
  exit 1
fi

# Count top-level inline comments belonging to that specific review.
# --paginate pulls every page so large PRs don't silently truncate.
gh api --paginate "repos/$REPO/pulls/$PR_NUM/comments?per_page=100" --jq \
  "[.[] | select(.user.login==\"Copilot\") | select(.in_reply_to_id==null) | select(.pull_request_review_id == $LAST_COPILOT_REVIEW_ID)] | length"
```

If that count is 0 AND the review's `submitted_at`
(`$LAST_COPILOT_REVIEW_AT`) is newer than your most recent commit's
author date, the latest pass was actually clean. The ID itself is a
monotonically-increasing integer, so comparing IDs to a commit would
be a type error; the timestamp is what's actually comparable.

Caveats:

- The count can be 0 because Copilot hasn't reviewed since your last
  push. Check the review's `submitted_at` is newer than your most
  recent commit's timestamp before trusting the zero.
- `LAST_COPILOT_REVIEW_ID` is empty when no Copilot review has ever
  run on the PR. The guard above treats that as "not ready" rather
  than "clean" — don't interpret silence as consent.
- Do NOT filter by `created_at >= submitted_at`. Empirically
  confirmed: inline comments on a Copilot review can have
  timestamps 1-2 seconds BEFORE the review's `submitted_at`, so a
  `>=` filter drops them. Use `pull_request_review_id` instead.

## Complement: zero unresolved conversation threads

The "zero new comments" signal is about INCOMING findings. The
complementary signal is about OUTGOING ones: every thread you
engaged with has been resolved. A PR with 0 new findings AND 0
unresolved threads is the cleanest merge state.

Placeholder note: `<owner>` is the org/user, `<name>` is the bare
repo name. Elsewhere in this doc `<owner>/<repo>` is the combined
slug passed to REST endpoints; GraphQL's `repository(owner:, name:)`
takes them as two separate fields, so this block uses `<name>`
deliberately.

```bash
# reviewThreads(first: 100) returns at most 100 threads — fine for
# ordinary PRs but silently undercounts on PRs with more than that.
# totalCount gives the exact number so we can sanity-check before
# relying on the isResolved-filter result.
gh api graphql -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          totalCount
          nodes { isResolved }
        }
      }
    }
  }' -F owner=<owner> -F name=<name> -F number=<N> \
  --jq '{
    total: .data.repository.pullRequest.reviewThreads.totalCount,
    sampled: (.data.repository.pullRequest.reviewThreads.nodes | length),
    unresolved: ([.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false)] | length)
  }'
```

If `total > sampled` (over 100 threads on the PR), paginate via
`pageInfo.endCursor` + `after:` before trusting the unresolved
count — see the pagination note in
[graphql-snippets.md](graphql-snippets.md).

Zero unresolved (when `total == sampled`) means every thread on the
PR has been explicitly closed (fixed, dismissed with evidence,
deferred with issue, or clarified + acted on). Humans skimming the
PR can trust that nothing slipped.

If this count is >0 but the "new findings" count is 0, you have
open threads you didn't resolve. Either resolve them now (if they
were addressed and you just forgot) or go back and act on them
(if they're actually pending).

## Secondary stop: Copilot repeats itself

A new comment is substantively the same as one you already addressed
(with a commit SHA or an evidence-backed dismissal). This happens
periodically — the model's context for the PR gets re-initialised and
it re-surfaces earlier findings.

Reply once, pointing at the original thread:

> Already addressed in `abc1234` (see earlier thread
> [link-to-first-reply]). No code change needed.

Do NOT change code to silence a repeated finding. That's how you end
up on round 8 fixing the same doc sentence three different ways.

After posting one "already addressed" reply per repeat, consider the
reviewer out of fresh signal and merge when the rest of the thread is
clean.

## Tertiary stop: volume drying up

Round 1: 7 findings. Round 2: 4. Round 3: 2. Round 4: 1 minor nit.
Round 5 is usually empty. If the volume is halving each round and the
remaining comments are stylistic or repeat-adjacent, the reviewer has
said what it was going to say.

Graph the count over rounds. If the curve flattens into the noise
floor (0-1 low-value comments per round), stop.

This is different from "ignore round-4+ comments". Every comment still
gets triaged (apply / dismiss / clarify / defer). The stop decision is about
whether to wait for another round, not whether to process comments
already on the PR.

## User escape hatch

If the human maintainer says "merge it", that overrides every other
signal. They have context you don't — maybe there's a release cutoff,
maybe the remaining comments are known non-issues, maybe they've
reviewed inline and are satisfied.

When the user says merge, merge. Don't re-litigate.

## Failure-mode stops

These are "stop and escalate" signals, not clean completions.

**Copilot is hallucinating at high volume.** Three or more consecutive
findings that verify false under the evidence check. The reviewer has
gone off the rails for this PR; flag it to the maintainer and propose
merging on human review only.

**The thread has devolved.** Comments are rephrasings of already-closed
threads, or suggestions that contradict comments from earlier rounds,
or style preferences stated with confidence but no supporting rule.
Flag, don't fix.

**CI is red for reasons unrelated to the PR's diff.** If the same
failure reproduces on `main`, it's pre-existing infra. Don't keep
force-pushing attempts to fix it in the PR; file or fix the infra
issue in its own PR, merge that first, rebase this PR, continue.

**A high-stakes "must fix" from Copilot that you can't verify.** If
Copilot says "this will leak secrets" or "this will crash in
production" and you can't confirm or refute after genuine
investigation, stop and ask the maintainer before merging. Don't merge
on hope.

## Anti-patterns — don't stop for these reasons

**"I've done N rounds, that feels like enough."** Round count isn't
the signal. Content is. If round 7 is still surfacing real issues,
keep going. If round 2 came back clean, stop.

**"The remaining comments are just style."** Real style violations
are real issues. The project has a style for a reason. Dismiss only
with evidence that the rule doesn't apply to the specific case, not
because style is "just" anything.

**"Copilot said this already."** Verify. Copilot sometimes surfaces a
subtle variant of an earlier finding — the surface is the same, the
underlying issue is different. Read before concluding "repeat".

**"The PR is taking too long."** Quality over speed, but also: if the
loop has been on for an hour+ and keeps surfacing real issues, the
root cause might be that the PR is too large. Consider splitting.

**"Admin merge will skip the remaining checks."** Only if you're
intentionally shipping unreviewed code. Don't admin-merge to "save
time" on review feedback; you just moved the review into the reports
that will follow.

## Putting it together

The stop decision is: "has the reviewer told me what it has to tell
me, and have I acted on it?"

- Zero new comments on the latest pass → yes and yes → merge.
- New comments are repeats of addressed threads → yes and yes (action
  was the earlier fix) → merge.
- Volume trending to zero, and each remaining comment has been
  triaged under the usual apply/dismiss/clarify/defer → yes and
  yes → merge. Triage the nits the same way as any other finding;
  don't skip them because they're small.
- User says merge → yes → merge.

If none of those fire and the reviewer is still producing signal, run
another round.
