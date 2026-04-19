# GraphQL + gh CLI snippets

Exact commands for interacting with Copilot reviews through the GitHub
API. All shell-safe; all assume `gh` is authenticated.

## Contents

- Copilot's bot ID (stable across repos)
- Re-request Copilot review after a push
- List a PR's inline comments (all, or latest round only)
- Reply to a specific inline comment
- Check which reviews exist and when
- Check CI status on the current PR head
- Get PR's GraphQL node ID
- Failure modes

## Copilot's bot ID

GitHub's Copilot PR reviewer has a stable global node ID:

```
BOT_kgDOCnlnWA
```

Use it in the `botIds` field of `requestReviews`. Do NOT pass it as
`userIds` — Copilot is a bot, not a user, and userIds will 404.

## Re-request review after a push

Push your fix commits first, then:

```bash
BOT_ID="BOT_kgDOCnlnWA"
PR_NUM=<pr-number>
REPO=<owner>/<repo>

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

**All inline comments (including replies):**

```bash
gh api "repos/$REPO/pulls/$PR_NUM/comments?per_page=100" --jq \
  '.[] | {id, user: .user.login, in_reply_to_id, line, path, body: (.body[0:120])}'
```

**Only Copilot's top-level comments from the latest round:**

```bash
# Find when the latest Copilot review was submitted
LAST_COPILOT=$(gh pr view "$PR_NUM" --repo "$REPO" --json reviews --jq \
  '[.reviews[] | select(.author.login=="copilot-pull-request-reviewer")] | last | .submittedAt')

# Pull only top-level comments (not replies) newer than that timestamp
gh api "repos/$REPO/pulls/$PR_NUM/comments?sort=created&direction=desc&per_page=100" --jq \
  "[.[] | select(.user.login==\"Copilot\") | select(.in_reply_to_id==null) | select(.created_at > \"$LAST_COPILOT\")] | .[] | {id, line, path, body: (.body[0:200])}"
```

`in_reply_to_id == null` filters out Copilot's replies to your replies
(which do happen occasionally).

## Reply to a specific inline comment

```bash
COMMENT_ID=<id-from-list-above>
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

## Check which reviews exist

```bash
gh pr view "$PR_NUM" --repo "$REPO" --json reviews --jq \
  '[.reviews[] | select(.author.login=="copilot-pull-request-reviewer")] | {count: length, last: last | .submittedAt}'
```

Useful for confirming whether a re-request actually fired a new pass.
If `last` hasn't advanced past the expected timestamp, Copilot hasn't
queued a review yet (sometimes takes a minute or two, sometimes the
re-request was dropped because there were no new commits to review
against).

## Check CI status on the current PR head

```bash
gh pr view "$PR_NUM" --repo "$REPO" --json statusCheckRollup --jq \
  '{
     failed: [.statusCheckRollup[] | select(.conclusion=="FAILURE") | .name],
     pending: [.statusCheckRollup[] | select(.status!="COMPLETED") | .name],
     passing: ([.statusCheckRollup[] | select(.conclusion=="SUCCESS")] | length)
   }'
```

Interpret:

- Empty `failed`, empty `pending` → ready to consider merging.
- Non-empty `failed` → investigate. If the same check also fails on
  `main`, it's infra (see `stop-conditions.md` "infra-red" case).
- Non-empty `pending` → wait; use a scheduled wake-up, not busy-poll.

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

Use the `/comments/<id>/replies` endpoint (review-comment replies), not
`/issues/comments/<id>` (issue comments). Inline PR comments are
separate from issue-style comments; different API surfaces.

### Batch reply shell loop prints huge GitHub response JSON

Pipe to `| head -1` or `| jq -c '.id'` to squelch the verbose response.
The reply succeeded if the response contains an `"id"` field; everything
else is noise.

## Further reading

- [GitHub REST API: pull request review comments](https://docs.github.com/en/rest/pulls/comments)
- [GitHub GraphQL: requestReviews mutation](https://docs.github.com/en/graphql/reference/mutations#requestreviews)
- `gh api --help` for CLI flags
