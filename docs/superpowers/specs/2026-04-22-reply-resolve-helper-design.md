# Reply+resolve batch helper — design

**Date:** 2026-04-22
**Issue:** [#4](https://github.com/qubitrenegade/github-pr-review-loop/issues/4)
**Type:** First real code change in the repo — ships a bash script under `tools/`. Prior issues (#5, #3, #2, #6, #7) were docs-only.

## Problem

The reply-and-resolve discipline adds real value during Copilot review loops: every comment thread gets closed with either a `Fixed in <sha> — rationale` reply or an evidence-backed Dismiss, then the thread gets marked resolved. At clickwork-1.0 scale (42 threads across 7 PRs, or 30–70 Copilot rounds in an 8–24-hour session), this discipline becomes a tax if you do it by hand.

Per-round, the boilerplate looks like:

```bash
# Map REST comment ids -> GraphQL thread ids
gh api graphql -f query='query(...) { ... reviewThreads { ... } }' --jq '...'

# Per-thread
reply() { gh api "repos/$REPO/pulls/$PR/comments/$1/replies" -f body="$2"; }
resolve() { gh api graphql -f query='mutation($t: ID!) { resolveReviewThread(...) }' -f t="$1"; }
reply 3106483445 "Fixed in abc1234 — ..."
resolve PRRT_kwDOR5QEuc58AHY4
# ... repeat per thread ...
```

The tax compounds: 5+ threads per round × 8+ rounds per PR × multiple PRs per wave. After 4–5 PRs, the skill's user (typically a Claude Code agent in a session) has hand-written the same two shell functions repeatedly and risks thread-id/comment-id mismatches along the way (observed once during this batch's own review loops).

Two primitives are worth extracting:

1. REST `comment_id` → GraphQL `thread_id` mapping, fetched once per PR invocation so the caller supplies only `comment_id`.
2. Reply + resolve for one thread as a single per-thread transaction (reply first, resolve after), with the batch continuing past any single-thread failure.

## Design

### Scope

First real code change in this skill repo. New files:

- `tools/reply-resolve.sh` — the helper (bash, ~50–80 lines).
- `tools/README.md` — usage, dependency note, Windows invocation note, example heredocs.

Edits to existing files:

- `skills/github-pr-review-loop/SKILL.md` — append a pointer sentence to "The loop" step 5.
- `skills/github-pr-review-loop/references/triage-patterns.md` — add a short paragraph to the "Batching multiple findings into one push" section pointing at the helper.
- `skills/github-pr-review-loop/references/graphql-snippets.md` — add a new section "Batching reply + resolve with `tools/reply-resolve.sh`" plus matching Contents entry.
- `README.md` (repo root) — brief mention of `tools/` if the README has a layout/what's-here block; skip otherwise.

**Out of scope:**

- PowerShell port — additive follow-up if demand emerges. The skill's existing `references/graphql-snippets.md` is already bash-only; anyone running the skill's existing content has already solved the "where's my bash" problem for their machine. Git for Windows ships bash at `C:\Program Files\Git\bin\bash.exe`; invoke via full path if not on PATH.
- Re-request-review logic — separate primitive, already documented as its own snippet.
- Caching the id-map to disk across invocations — fetch-per-invocation is one GraphQL call; disk-cache complexity isn't worth it at batch sizes this skill targets.
- Parallelism across threads — sequential per-thread keeps error output sane and GitHub REST is friendly to serial calls.
- Retries on transient `gh` failures — `gh api` already has reasonable defaults; permanent-fail cases don't benefit from retry.
- Unit test harness (mock gh CLI, bats framework) — over-investment for ~60 lines of shell. Manual smoke test + Copilot review is the pragmatic verification.

### Design choices (locked in during brainstorm)

- **Bash script, not Python / gh extension.** The skill's existing references (graphql-snippets.md) are bash-only; shipping a bash helper keeps the dependency footprint identical to what's already assumed. Python would widen the dep surface; a gh CLI extension is additive follow-up work, not blocking.
- **NDJSON-on-stdin input**, not TSV. TSV breaks on multi-line reply bodies; NDJSON handles arbitrary body content cleanly via `jq` parsing. User writes one JSON object per line in a heredoc or pipes from a file.
- **Tool-side `${SHA}` template substitution** via `--sha` flag, not shell-side pre-interpolation. Works identically for heredoc and file-on-disk inputs. Also nudges toward always citing the commit SHA explicitly (part of the Apply discipline). If `--sha` is missing but a body references `${SHA}`, the script errors before any HTTP — fail-fast prevents a raw `${SHA}` placeholder from landing in a real PR comment.
- **Best-effort sequential per-thread**, not fail-fast batch: one thread's failure doesn't abort the batch. Within a thread, reply first then resolve; if resolve fails after reply succeeds, the thread ends up replied-but-unresolved, which is the safe default state.
- **Dual output: stdout NDJSON (machine) + stderr human-readable (operator).** Exit code `0` = all succeeded; `1` = at least one failure. Final stderr line summarizes counts.

### CLI contract

**Invocation:**

```bash
tools/reply-resolve.sh --repo <owner>/<name> --pr <N> [--sha <hash>] [--dry-run] < input.ndjson
```

- `--repo` and `--pr` required. `<N>` accepts any integer; no local-clone requirement.
- `--sha` optional. When provided, the script substitutes `${SHA}` in every reply body before posting. If a body references `${SHA}` and `--sha` wasn't passed, the script errors (exit 2) before any HTTP calls.
- `--dry-run` optional. Prints what would happen (per-thread: `comment_id`, resolved body after `${SHA}` substitution, matched `thread_id`) without POSTing or mutating.

**Stdin — NDJSON, one reply per line:**

```json
{"comment_id": 12345, "body": "Fixed in `${SHA}` — commands_dir is Path"}
{"comment_id": 67890, "body": "Fixed in `${SHA}` — same fix applied"}
```

Each line is a standalone JSON object with exactly two fields: `comment_id` (integer) and `body` (string). Parsed with `jq`; malformed lines fail the batch.

**Output:**

- **stdout** — NDJSON status per input line, in input order:
  ```json
  {"comment_id":12345,"thread_id":"PRRT_...","reply_id":99887766,"resolved":true,"status":"ok"}
  {"comment_id":67890,"thread_id":null,"reply_id":null,"resolved":false,"status":"error","error":"no thread found for comment 67890"}
  ```
- **stderr** — human-readable per-line progress (`✓ 12345 replied+resolved` / `✗ 67890 reply failed: <gh error>`) and a final `X/Y succeeded, Z failed` summary.
- **Exit code** — `0` if every line succeeded, `1` if any failed.

**Error semantics:**

- Per-thread best-effort: attempt reply → attempt resolve → move to next. One failure doesn't abort the batch.
- Within one thread: reply first; if reply fails, skip resolve and mark error. If reply succeeds but resolve fails, emit partial-success status line with `resolved: false`.
- `--sha` missing but `${SHA}` referenced anywhere in input: exit 2 before any HTTP.
- Id-map GraphQL fetch failure: exit 3 before any per-thread attempts.

### Internal flow

Script structure (bash, ~50–80 lines):

**1. Arg parsing & validation**

`while/case` loop for `--repo`, `--pr`, `--sha`, `--dry-run`, `--help`. Validate both required flags present; validate `--pr` is an integer. Read stdin once into a variable so we can scan for `${SHA}` before HTTP.

**2. `${SHA}` template pre-check**

If any input line's `body` contains the literal `${SHA}` and `--sha` wasn't passed: print `ERROR: body references ${SHA} but --sha wasn't provided` to stderr, exit 2.

**3. Fetch the id-map (once per invocation)**

One GraphQL call:

```graphql
query ($owner: String!, $name: String!, $number: Int!) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        totalCount
        nodes {
          id
          comments(first: 1) { nodes { databaseId } }
        }
      }
    }
  }
}
```

Parse with `jq` into a JSON map `{ "<comment_id>": "<thread_id>", ... }`. Keep as a variable; look up per-thread with `jq -r --argjson id N '.[$id | tostring] // empty'`.

If `totalCount > 100`: print `ERROR: PR has >100 threads; v1 of this script doesn't paginate. File an issue if you hit this.` to stderr and exit 3.

If the GraphQL call fails: error, exit 3, no per-thread attempts.

**4. Per-line processing loop**

```
for each NDJSON input line:
  parse comment_id and body via jq
  if body contains ${SHA}: substitute SHA value into body
  look up thread_id from the id-map
  if no match: emit error status (stdout + stderr), continue

  if --dry-run: print what would happen (comment_id, thread_id, body), continue

  # reply via REST
  POST repos/$REPO/pulls/$PR/comments/$COMMENT_ID/replies -f body="$BODY"
  capture reply_id on success
  if fails: emit error status (reply_id=null, resolved=false), continue (skip resolve)

  # resolve via GraphQL
  mutation resolveReviewThread(threadId: $THREAD_ID)
  if fails: emit partial status (reply_id set, resolved=false, error=...)
  else: emit success status (reply_id set, resolved=true)
```

**5. Final summary on stderr**

Count successes and failures, print `X/Y succeeded, Z failed` on the last stderr line.

Exit `0` if Z=0, else `1`.

### Example usage

Heredoc (the common case):

```bash
SHA=$(git rev-parse --short HEAD)
tools/reply-resolve.sh --repo qubitrenegade/github-pr-review-loop --pr 42 --sha "$SHA" <<EOF
{"comment_id": 3106483445, "body": "Fixed in \`\${SHA}\` — commands_dir is a Path, not a string."}
{"comment_id": 3106483456, "body": "Fixed in \`\${SHA}\` — same fix applied."}
EOF
```

File input (for agent workflows that build the NDJSON programmatically):

```bash
cat replies.ndjson | tools/reply-resolve.sh --repo qubitrenegade/github-pr-review-loop --pr 42 --sha abc1234
```

Dry-run to verify before the real call:

```bash
tools/reply-resolve.sh --repo qubitrenegade/github-pr-review-loop --pr 42 --sha abc1234 --dry-run < replies.ndjson
```

### SKILL.md pointer

In `## The loop`, step 5 currently reads (after the landed Acknowledge-exception clause):

> 5. Post inline replies with commit SHAs / empirical dismissals / follow-up issue links. Resolve each thread after replying (**except Acknowledge threads, which stay unresolved pending maintainer decision — see "After replying, resolve the conversation"**).

Append a second sentence to that step:

> For batches of more than two threads per round, `tools/reply-resolve.sh` handles the reply+resolve roundtrip — see `tools/README.md`.

### triage-patterns.md pointer

The `## Batching multiple findings into one push` section lays out the batch pattern. Before the "Sweep before you push" subsection that follows the main bullet list, append a short paragraph:

> For the reply-and-resolve step specifically (processing many threads in one round), `tools/reply-resolve.sh` at the repo root takes NDJSON on stdin and handles the full reply+resolve transaction per thread. See `tools/README.md` for usage.

### graphql-snippets.md additions

**Contents TOC** — add a new entry between "Reply to a specific inline comment" and "List review threads with resolved state":

```
- Batching reply + resolve with `tools/reply-resolve.sh`
```

**New section body** (insert between the "Reply to a specific inline comment" section and the "List review threads with resolved state" section):

```markdown
## Batching reply + resolve with `tools/reply-resolve.sh`

The raw `/comments/<id>/replies` POST and `resolveReviewThread` mutation snippets above are the primitives. For batches (more than two threads per round), `tools/reply-resolve.sh` at the repo root wraps both into a single per-thread transaction, handles the REST `comment_id` → GraphQL `thread_id` lookup internally, and supports `${SHA}` templating. See `tools/README.md` for usage.
```

### README.md (root) update

If the root `README.md` has a layout / "What's here" block, add an entry:

```
- `tools/` — helper scripts (see `tools/README.md`). `reply-resolve.sh` batches reply+resolve during Copilot review loops.
```

If the README doesn't have such a block, skip.

## Verification

Smoke-test-style, since this is real code:

1. **Manual smoke test on a real PR** — find a PR with 2–3 unresolved Copilot threads (any historic one from this batch works). Run with `--dry-run` first; confirm id-map lookup prints correct `comment_id → thread_id` pairs and the body text is `${SHA}`-substituted as expected. Then run without `--dry-run`; verify the threads actually got replied AND resolved.
2. **Error-path checks** (dry-run suffices):
   - Body references `${SHA}` but `--sha` not passed → exits 2 before any HTTP.
   - Malformed NDJSON line → exits early with jq error.
   - `comment_id` with no matching thread → prints per-line error, batch continues.
3. **Help/usage** — `--help` or missing required flags prints a clean usage block.
4. **Copilot review loop** on the PR that ships the helper. Dogfood — and this will itself be one of the first batches the helper handles.

No automated tests. The script is thin enough that code review + the smoke test cover the ground.

## Out-of-scope / follow-ups

After this PR merges, all six issues in the batch (#5, #3, #2, #6, #7, #4) that motivated this spec → plan → implement cycle are resolved.

Possible future additions (not blocking):

- PowerShell port for Windows users without bash in PATH.
- GraphQL pagination for PRs with >100 review threads.
- A companion `tools/rerequest-review.sh` wrapping the `requestReviews` mutation.
- Promotion to a `gh` CLI extension (`gh review-loop reply-resolve ...`) if the script sees enough use to justify distribution.
