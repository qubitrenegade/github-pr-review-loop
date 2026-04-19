# GraphQL + gh CLI snippets

Exact commands for interacting with Copilot reviews through the GitHub
API.  All snippets assume `gh` is authenticated and that the shell
variables below are set; populate them before running anything in
this file so the commands are copy-paste-safe:

```bash
OWNER="<owner>"          # e.g. qubitrenegade
NAME="<repo>"            # bare repo name, e.g. github-pr-review-loop
REPO="$OWNER/$NAME"      # combined slug for REST endpoints
PR_NUM="<pr-number>"     # e.g. 42
```

Why a preamble + why the quotes around the RHS: angle-bracket
placeholders like `<owner>` are I/O redirection tokens in bash/zsh,
even inside an assignment (`OWNER=<owner>` tries to read from a
file named `owner` and fails with "No such file or directory").
Quoting `<owner>` on the RHS makes the placeholder a string literal
so the line is copy-paste-safe, then the user substitutes the real
value.  Downstream commands reference `"$OWNER"` / `"$REPO"` /
etc, which is both safe and idiomatic.

## Contents

- Copilot's bot ID (observed github.com value + runtime discovery)
- Re-request Copilot review after a push
- List a PR's inline comments (all, or latest round only)
- Reply to a specific inline comment
- List review threads with their resolved state + thread IDs
- Resolve a review thread after replying
- Bulk-resolve all threads you've already replied to
- Check which reviews exist and when
- Check CI status on the current PR head
- Get PR's GraphQL node ID
- Failure modes

## Copilot's bot ID

On github.com, Copilot's PR reviewer is a `Bot` account with this
global node ID:

```
BOT_kgDOCnlnWA
```

Observed stable across the clickwork 1.0 cycle (Apr 2026). GraphQL
node IDs are opaque implementation details in principle — the skill
treats this value as the github.com default and provides a discovery
helper below for anyone on GitHub Enterprise, a different instance,
or a future github.com where the ID has rotated.

Use it in the `botIds` field of `requestReviews`. Do NOT pass it as
`userIds` — Copilot is a bot, not a user, and the mutation typically
returns a GraphQL error (often still HTTP 200) like `Could not
resolve to User node` rather than a 404.

### Gotcha: Copilot's identifier across APIs

Copilot's identifier is not consistent across GitHub's API surfaces.
Three distinct **login strings** appear depending on which endpoint
you hit (plus a separate `user.type` field that's always `Bot` for
account-shape disambiguation):

| API endpoint | Field | Value |
|---|---|---|
| REST `/pulls/<N>/comments` | `user.login` | `Copilot` |
| REST `/pulls/<N>/comments` | `user.type` | `Bot` |
| REST `/pulls/<N>/reviews` | `user.login` | `copilot-pull-request-reviewer[bot]` |
| GraphQL `reviews.nodes[].author.login` | | `copilot-pull-request-reviewer` |
| GraphQL `reviewThreads.nodes[].comments.nodes[].author.login` | | `copilot-pull-request-reviewer` |

Match by endpoint when filtering:
- REST comments → `"Copilot"`
- REST reviews → `"copilot-pull-request-reviewer[bot]"` (note the `[bot]` suffix)
- GraphQL anywhere → `"copilot-pull-request-reviewer"` (no suffix)

Getting this wrong silently returns an empty result — no error, just
zero matches. Double-check with one unfiltered query first if your
filter returns unexpectedly empty.

### Discovering the bot ID at runtime

If `BOT_kgDOCnlnWA` doesn't work (wrong instance, rotated ID, etc.),
look it up from an existing Copilot review on any PR in the repo:

```bash
gh api graphql -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviews(last: 50) {
          nodes {
            author {
              __typename
              ... on Bot { id login }
              ... on User { id login }
            }
          }
        }
      }
    }
  }' -F owner="$OWNER" -F name="$NAME" -F number="$PR_NUM" \
  --jq '.data.repository.pullRequest.reviews.nodes[] | select(.author.__typename == "Bot") | select(.author.login == "copilot-pull-request-reviewer") | .author | {id, login}'
```

`last: 50` pulls the 50 most recent reviews rather than the oldest
50. On a PR that's been through many review cycles (especially
multi-round loops), Copilot's reviews are near the end of the
timeline; using `first:` without an `orderBy` can skip them. 50
covers the typical review-loop depth (clickwork 1.0 topped out
around 8 per PR); if you're on a PR that has genuinely had more
than 50 reviews, pass `after:` cursor pagination or pick a less
saturated PR from the same repo.

The extra `login == "copilot-pull-request-reviewer"` filter is so
the query stays unambiguous on repos that use other bot reviewers
(CI bots, third-party review services) which would otherwise also
match `__typename == "Bot"`. If GitHub ever renames Copilot's bot
account, drop the login filter, see all matching Bot reviews, and
identify the right one manually.

Any PR that has already been reviewed by Copilot will work. Save the
resulting `id` as your `BOT_ID` for the `requestReviews` mutation.

## Re-request review after a push

Push your fix commits first, then:

```bash
BOT_ID="BOT_kgDOCnlnWA"
# PR_NUM and REPO come from the shell-setup preamble at the top of this file.

PR_ID=$(gh pr view "$PR_NUM" --repo "$REPO" --json id --jq .id)

gh api graphql -f query='
  mutation($prId: ID!, $botId: ID!) {
    requestReviews(input: {pullRequestId: $prId, botIds: [$botId]}) {
      pullRequest { number }
    }
  }' -f prId="$PR_ID" -f botId="$BOT_ID"
```

Expected response:

```json
{"data":{"requestReviews":{"pullRequest":{"number":<N>}}}}
```

Copilot will typically start a new review within 30-90 seconds.

## List inline comments on a PR

Use `--paginate` so large PRs don't silently truncate at 100
comments. A single page is 100 items; `--paginate` walks every page
and concatenates the JSON arrays.

**All inline comments (including replies):**

```bash
gh api --paginate "repos/$REPO/pulls/$PR_NUM/comments?per_page=100" --jq \
  '.[] | {id, user: .user.login, in_reply_to_id, line, path, body: (.body[0:120])}'
```

**Only Copilot's top-level comments from the latest round:**

Filter by `pull_request_review_id`, not by timestamp. Review comments
on GitHub are created a second or two BEFORE the parent review's
`submitted_at` (the comments exist during review composition; the
review is finalised last). Timestamp comparisons like
`created_at >= submitted_at` miss those earlier-by-a-second comments
and return false "zero new findings" readings.

```bash
# Get the latest Copilot review's integer ID from REST. Note the
# REST-reviews endpoint uses "copilot-pull-request-reviewer[bot]"
# (with a [bot] suffix) — different from the REST-comments "Copilot"
# and the GraphQL "copilot-pull-request-reviewer".
LAST_COPILOT_REVIEW_ID=$(gh api --paginate "repos/$REPO/pulls/$PR_NUM/reviews?per_page=100" --jq \
  '[.[] | select(.user.login=="copilot-pull-request-reviewer[bot]")] | last | .id // empty')

if [ -z "$LAST_COPILOT_REVIEW_ID" ]; then
  echo "No Copilot review yet on this PR." >&2
  exit 1
fi

# Pull only top-level comments (not replies) that belong to that
# specific review — the review-id match is exact, no timestamp race.
gh api --paginate "repos/$REPO/pulls/$PR_NUM/comments?per_page=100" --jq \
  "[.[] | select(.user.login==\"Copilot\") | select(.in_reply_to_id==null) | select(.pull_request_review_id == $LAST_COPILOT_REVIEW_ID)] | .[] | {id, line, path, body: (.body[0:200])}"
```

`in_reply_to_id == null` filters out Copilot's replies to your replies
(which do happen occasionally).

Without `--paginate`, a PR with >100 comments will silently drop
everything after the first page and you can get a false "clean
round" reading.

## Reply to a specific inline comment

```bash
COMMENT_ID="<id-from-list-above>"
gh api "repos/$REPO/pulls/$PR_NUM/comments/$COMMENT_ID/replies" \
  -f body="Fixed in abc1234 — concise description of the fix."
```

For batch replies across many findings, drive this in a shell loop:

```bash
reply() {
  gh api "repos/$REPO/pulls/$PR_NUM/comments/$1/replies" -f body="$2"
}

reply 3106073129 "Fixed in acc31d3 — stub now forwards non-clickwork queries through the real impl."
reply 3106083785 "Fixed in 0e9fc99 — switched to git+https."
reply 3106088847 "Dismissing — see evidence: \`grep -c common-footguns docs/LLM_REFERENCE.md\` returns 1."
```

## List review threads with resolved state

Threads are the grouping above individual inline comments — each
thread has an `isResolved` flag that drives the PR's "unresolved
conversations" counter. To work with thread resolution you need the
thread ID (not the comment ID).

Variable convention for this file: `REPO=<owner>/<repo>` for REST
endpoints (`repos/$REPO/...`), and `OWNER=<owner>` + `NAME=<repo>`
as two separate fields for GraphQL `repository(owner:, name:)`
queries. Don't reuse `REPO` as the bare-name GraphQL variable —
copy/paste across sections will break.

**Pagination note.** `reviewThreads(first: 100)` returns the first
100 threads. Most PRs have fewer; the clickwork 1.0 PRs maxed out
around 15 threads each. For a PR with more than 100 threads, this
query silently undercounts — both the listing and any
"unresolved === 0" check downstream become wrong. If your PR has
over ~80 threads, loop with the GraphQL `pageInfo.endCursor` +
`after:` cursor; for everyday PRs the simple form below is fine.
Add a `totalCount` read on `reviewThreads` if you want an early
check:

```graphql
reviewThreads(first: 1) { totalCount }
```

```bash
# OWNER, NAME, PR_NUM from the shell-setup preamble.

gh api graphql -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          nodes {
            id
            isResolved
            comments(first: 5) {
              nodes {
                id
                author { login }
                body
              }
            }
          }
        }
      }
    }
  }' -F owner="$OWNER" -F name="$NAME" -F number="$PR_NUM" \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | {id, isResolved, first_author: .comments.nodes[0].author.login, first_body: .comments.nodes[0].body[0:100]}'
```

Shows each thread's ID, whether it's resolved, and the opener's
login + first 100 chars of their comment (enough to map thread IDs
to the findings you're tracking).

## Resolve a review thread after replying

After you've posted your reply (apply SHA / dismiss evidence / defer
+ issue link), mark the thread resolved:

```bash
THREAD_ID="<from reviewThreads query above>"
gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) {
      thread { isResolved }
    }
  }' -f threadId="$THREAD_ID"
```

Expected response:

```json
{"data":{"resolveReviewThread":{"thread":{"isResolved":true}}}}
```

To unresolve (rare — usually when reopening a debate):

```bash
gh api graphql -f query='
  mutation($threadId: ID!) {
    unresolveReviewThread(input: {threadId: $threadId}) {
      thread { isResolved }
    }
  }' -f threadId="$THREAD_ID"
```

## Bulk-resolve all threads you've already replied to

Common case after a round of fixes: you've replied to 6 threads
with apply SHAs, now you want to resolve them all in one shot.

```bash
# OWNER, NAME, PR_NUM from the shell-setup preamble.  ME is new:
ME="<your-github-login>"   # e.g. qubitrenegade

# 1. Get all unresolved threads
UNRESOLVED=$(gh api graphql -f query='
  query($owner: String!, $name: String!, $number: Int!) {
    repository(owner: $owner, name: $name) {
      pullRequest(number: $number) {
        reviewThreads(first: 100) {
          nodes { id isResolved comments(last: 20) { nodes { author { login } } } }
        }
      }
    }
  }' -F owner="$OWNER" -F name="$NAME" -F number="$PR_NUM" \
  --jq '.data.repository.pullRequest.reviewThreads.nodes[] | select(.isResolved == false) | select([.comments.nodes[].author.login] | any(. == "'"$ME"'")) | .id')

# 2. Resolve each. Use `while read` instead of unquoted `for` so
# whitespace or newline-containing IDs can't trip the shell's word
# splitting. Thread IDs don't contain whitespace today, but this is
# defensive-by-default.
while IFS= read -r tid; do
  [ -z "$tid" ] && continue
  gh api graphql -f query='
    mutation($threadId: ID!) {
      resolveReviewThread(input: {threadId: $threadId}) {
        thread { isResolved }
      }
    }' -f threadId="$tid" >/dev/null
  echo "Resolved $tid"
done <<< "$UNRESOLVED"
```

The filter `any(author == $ME)` limits resolution to threads YOU
replied on. Don't bulk-resolve threads you haven't actually engaged
with; that's drive-by closing without evidence.

`comments(last: 20)` pulls the most recent 20 comments from each
thread (not the earliest 20). Your reply is the most recent comment
you made on the thread, so `last:` makes the "have I replied?" check
reliable even on threads with more than 20 comments. For the edge
case of a thread with 20+ comments where YOUR reply is older than
the 20 most-recent, raise the limit or paginate.

## Check which reviews exist

```bash
gh pr view "$PR_NUM" --repo "$REPO" --json reviews --jq \
  '[.reviews[] | select(.author.login=="copilot-pull-request-reviewer")] | {count: length, last: (last | .submittedAt)}'
```

Useful for confirming whether a re-request actually fired a new pass.
If `last` hasn't advanced past the expected timestamp, Copilot hasn't
queued a review yet (sometimes takes a minute or two, sometimes the
re-request was dropped because there were no new commits to review
against).

## Check CI status on the current PR head

Whitelist-based: `SUCCESS`, `SKIPPED`, and `NEUTRAL` count as green
(matches GitHub's own merge gate — NEUTRAL is treated as success for
required checks). Any other completed conclusion (FAILURE,
CANCELLED, TIMED_OUT, ACTION_REQUIRED, STARTUP_FAILURE) blocks merge.

```bash
gh pr view "$PR_NUM" --repo "$REPO" --json statusCheckRollup --jq \
  '{
     blocking: [.statusCheckRollup[]? | select(.status == "COMPLETED" and .conclusion != "SUCCESS" and .conclusion != "SKIPPED" and .conclusion != "NEUTRAL") | {name, conclusion}],
     pending: [.statusCheckRollup[]? | select(.status != "COMPLETED") | .name],
     green: ([.statusCheckRollup[]? | select(.status == "COMPLETED" and (.conclusion == "SUCCESS" or .conclusion == "SKIPPED" or .conclusion == "NEUTRAL"))] | length)
   }'
```

Interpret:

- Empty `blocking`, empty `pending` → every completed check is green
  (SUCCESS, SKIPPED, or NEUTRAL), nothing in-flight → ready to
  consider merging.
- Non-empty `blocking` → investigate by conclusion. FAILURE means
  fix the code or the workflow (infra if the same check also fails
  on `main` — see `stop-conditions.md` "failure-mode stops"
  section). CANCELLED / TIMED_OUT usually means re-run.
  ACTION_REQUIRED usually means a first-time-contributor approval
  or secret-access prompt.
- Non-empty `pending` → wait; use a scheduled wake-up, not busy-poll.

Why not a FAILURE-only filter: GitHub's check conclusions include
CANCELLED, TIMED_OUT, ACTION_REQUIRED, and STARTUP_FAILURE. A
blacklist on FAILURE lets those slip through and falsely flags the
PR as green when a required check was killed mid-run or is waiting
on manual intervention.

Why NEUTRAL is in the green set: GitHub's required-status-check and
dependent-check logic both treat NEUTRAL as a passing outcome.
Tools (linters, code-scanners) that want to signal "I ran and found
nothing actionable" use NEUTRAL rather than SUCCESS. Treating it as
blocking would be stricter than GitHub's own merge gate.

## Get the PR's GraphQL node ID (used by mutations)

```bash
gh pr view "$PR_NUM" --repo "$REPO" --json id --jq .id
```

Format is `PR_xxxxxxxxxx...` — passed as `$prId` to mutations.

## Failure modes

### "Could not resolve to User node" on `requestReviews`

You used `userIds: [...]` instead of `botIds: [...]`. Copilot is a bot.
Fix the mutation:

```diff
- requestReviews(input: {pullRequestId: $prId, userIds: [$botId]})
+ requestReviews(input: {pullRequestId: $prId, botIds: [$botId]})
```

### `requestReviews` succeeds but no new review appears

Possible causes, in order of likelihood:

1. **No new commits on the PR since the last review.** Copilot
   deduplicates. Push at least one commit (even a tiny doc fix)
   between review requests.
2. **Copilot reviewer disabled on the repo.** Settings → General →
   Features → Copilot code review. Turn it on for the repo or org.
3. **PR is in a draft state.** Copilot won't review draft PRs on
   some configurations. Mark as ready for review.
4. **Rate limit.** Rare but possible on very rapid review cycles.
   Wait a minute and retry.

### Comment replies are 404-ing on valid-looking IDs

Use the PR review-comment reply endpoint
`POST /repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies`
— note the `{pull_number}` in the path — not the issue-comments endpoint
`/repos/{owner}/{repo}/issues/comments/{comment_id}` (which is for
top-level issue-style comments). Inline PR review comments and
issue-style comments live on different API surfaces.

### Batch reply shell loop prints huge GitHub response JSON

Pipe to `| head -1` or `| jq -c '.id'` to squelch the verbose response.
The reply succeeded if the response contains an `"id"` field; everything
else is noise.

## Further reading

- [GitHub REST API: pull request review comments](https://docs.github.com/en/rest/pulls/comments)
- [GitHub GraphQL: requestReviews mutation](https://docs.github.com/en/graphql/reference/mutations#requestreviews)
- `gh api --help` for CLI flags
