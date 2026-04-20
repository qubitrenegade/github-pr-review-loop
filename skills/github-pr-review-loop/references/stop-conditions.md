# Stop conditions

When to stop chasing a Copilot review loop, and the merge gate that
still has to clear before you actually merge. Concrete signals, not
arbitrary thresholds.

## Contents

- Merge precondition: required CI checks are green
- Merge precondition: user authorization
- Primary stop: zero new findings on a Copilot pass
- Complement: zero unresolved conversation threads
- Secondary stop: Copilot repeats itself
- Tertiary stop: suggestion volume dries up
- User override of the review loop
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

Set env vars first so the snippets are copy-paste-safe (angle-bracket
placeholders like `<N>` are I/O redirection tokens in bash/zsh even
inside assignments; quote them on the RHS):

```bash
REPO="<owner>/<repo>"    # e.g. qubitrenegade/github-pr-review-loop
PR_NUM="<N>"             # e.g. 42
```

```bash
gh pr view "$PR_NUM" --repo "$REPO" --json statusCheckRollup --jq \
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

## Merge precondition: user authorization

User authorization is one of three merge gates, peer to the CI and Copilot review loop gates. None of the three alone implies permission to merge.

Two modes grant the authorization:

- **Standing** — the maintainer is in the session and makes the merge call themselves (in-session "merge it", or the routine case of hitting the merge button after a review pass).
- **Conditional grant** — the maintainer grants permission up-front with scoped caveats, typically before stepping away. Template:

  > "Merge when Copilot returns zero new comments AND CI is green. Wait for me if there are repeated comments, comments you have questions about, or red CI."

Any triggered caveat revokes the grant and returns to the default ("wait for maintainer"). Don't reinterpret caveats in light of how close the PR feels to merging — the whole point of caveat language is to stop you when a particular signal fires, regardless of surrounding context.

Absent a grant, the default is ping + wait. A converged review loop + green CI alone is NOT permission to merge. Every merge needs all three gates: CI green (above), review loop converged (below), and user authorization (this section).

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
REPO="<owner>/<repo>"
PR_NUM="<N>"

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
**committer** date, the latest pass was actually clean.

```bash
# Run from inside the checkout of $REPO, or set REPO_DIR to the
# local path (REPO_DIR="<local-path-to-clone>"; then
# git -C "$REPO_DIR" ...).
LATEST_COMMIT_DATE=$(git log -1 --format=%cI HEAD)
# then:  "$LAST_COPILOT_REVIEW_AT" > "$LATEST_COMMIT_DATE"  (ISO-8601 string
# compare works correctly)
```

Why committer date and not author date: author date is preserved
across rebase / cherry-pick / am-patch, so it can be arbitrarily old
for a commit that just landed on the branch. Copilot still reviews
the head at its current committer time, so comparing to the author
date can mark a fresh review as "stale" and chase a false failure.
The committer date is updated on every git operation that writes
the commit, which is what you actually care about.

The review ID itself is a monotonically-increasing integer, so
comparing IDs to a commit would be a type error; the timestamp is
what's actually comparable.

Caveats:

- The count can be 0 because Copilot hasn't reviewed since your last
  push. Check the review's `submitted_at` is newer than your most
  recent commit's **committer** date (`git log -1 --format=%cI HEAD`)
  before trusting the zero.
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
repo name. Earlier blocks in this doc used `REPO="<owner>/<repo>"` —
the combined slug for REST endpoints. GraphQL's
`repository(owner:, name:)` takes them as two separate fields, so
this block needs three shell vars (the PR number is also referenced
below):

```bash
OWNER="<owner>"          # e.g. qubitrenegade
NAME="<name>"            # bare repo name, e.g. github-pr-review-loop
PR_NUM="<N>"             # e.g. 42 — same value as the REST sections'
                         # PR_NUM if you're running from the same shell
```

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
  }' -F owner="$OWNER" -F name="$NAME" -F number="$PR_NUM" \
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

**Acknowledge threads count as unresolved, intentionally.** On plan or spec PRs with open design questions, Acknowledge threads (where Copilot voted on a maintainer-authority decision — see [triage-patterns.md](triage-patterns.md) under "Acknowledge") stay unresolved until the maintainer decides. These are not "forgotten to resolve" — they are actively signaling "a design question is still open." The merge gate treats them the same as any other unresolved thread, which is the forcing function: the plan doesn't merge until the design is locked. If the unresolved count is N and all N are Acknowledge threads, the gate is correctly blocking — the remedy is maintainer decisions, not clicking Resolve.

If this count is >0 but the "new findings" count is 0, you have
open threads you didn't resolve. Either resolve them now (if they
were addressed and you just forgot) or go back and act on them
(if they're actually pending). **Exception:** Acknowledge threads on plan or spec PRs are pending maintainer decision, not forgotten — see the note above.

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
gets triaged (apply / dismiss / clarify / defer / acknowledge). The stop decision is about
whether to wait for another round, not whether to process comments
already on the PR.

**Mode-shift sub-signal.** On plan or spec PRs, "volume drying up" often has a characteristic shape: the first few rounds surface prose-level issues (factual errors, stale references, internal inconsistencies) which get applied or dismissed normally. Once the prose stabilises, Copilot shifts modes and starts voting on the open design questions embedded in the doc — the round is no longer surfacing bugs, it's surfacing Acknowledge-class findings (see [triage-patterns.md](triage-patterns.md) under "Acknowledge"). That mode shift is itself a stop signal: the plan doc is substantively clean; the remaining work is the maintainer's decision, not another Copilot round. When a round's findings are predominantly Acknowledge, the review loop has done what it can, and what unblocks progress next is maintainer time, not another re-request.

## User override of the review loop

If the maintainer says "stop" in-session, that overrides every other review-loop signal for continuing the review. Don't re-litigate. If the maintainer says "merge it," treat that under "Merge precondition: user authorization" above rather than in this override section — "merge it" is a merge-authorization signal, not a review-loop-stop signal.

This section exists because explicit maintainer "stop" (without an accompanying merge instruction) is a valid review-loop-stop signal: "I don't want you chasing this PR any further, regardless of whether it's merging now." Respect it.

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

- Zero new comments on the latest pass → review signal exhausted. Merge if CI green AND user authorized (standing or conditional grant); otherwise stop chasing and ping maintainer.
- New comments are repeats of addressed threads → review signal exhausted (action was the earlier fix). Merge if CI green AND user authorized; otherwise stop chasing and ping maintainer.
- Volume trending to zero, and each remaining comment has been triaged under the usual apply/dismiss/clarify/defer/acknowledge → review signal exhausted. Merge if CI green AND user authorized; otherwise stop chasing and ping maintainer. Triage the nits the same way as any other finding; don't skip them because they're small.
- User says merge → merge authorization gate is satisfied (Standing mode). Verify CI green and that the review loop has at least one stop signal fired before merging — "merge authorization" alone doesn't skip the other two gates.

If none of those fire and the reviewer is still producing signal, run
another round.
