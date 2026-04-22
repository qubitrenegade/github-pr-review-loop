# Reply+Resolve Helper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `tools/reply-resolve.sh` (first real code in the skill repo) per the spec at `docs/superpowers/specs/2026-04-22-reply-resolve-helper-design.md` — a bash helper that batches the reply-and-resolve roundtrip during Copilot review loops, reading NDJSON on stdin and replying/resolving per thread against a target PR.

**Architecture:** Single-commit implementation PR ships two new files (`tools/reply-resolve.sh` + `tools/README.md`) and makes four small pointer edits across existing skill docs. No unit test harness — the script is thin enough that manual smoke-test + Copilot review is the pragmatic verification per the spec. Shell is bash; dependencies are `gh` + `jq` (already assumed by the skill's existing snippets).

**Tech Stack:** bash, `gh` CLI, `jq`. Git. Markdown for docs.

**Branch:** `docs/implement-reply-resolve-helper-4` (already created, based on `main` at `955b45b`).

**Repo:** `qubitrenegade/github-pr-review-loop`.

**Spec reference (authoritative):** `docs/superpowers/specs/2026-04-22-reply-resolve-helper-design.md`. Every task cites the spec section it implements.

---

## File Structure

**New files:**

- `tools/reply-resolve.sh` — the helper (bash, ~90–130 lines with teaching-style comments). Single responsibility: given a PR and an NDJSON batch of `{comment_id, body}` pairs, replies to each comment and resolves the corresponding thread, emitting per-line status on stdout + human progress on stderr.
- `tools/README.md` — usage documentation. Single responsibility: describe the helper's CLI, input format, output format, and Windows invocation note.

**Modified files:**

- `skills/github-pr-review-loop/SKILL.md` — one added sentence to "The loop" step 5.
- `skills/github-pr-review-loop/references/triage-patterns.md` — one added paragraph inside the "Batching multiple findings into one push" section.
- `skills/github-pr-review-loop/references/graphql-snippets.md` — one new section + one Contents entry.
- `README.md` (repo root) — one line added to the Structure block.

---

## Task 1: Create `tools/reply-resolve.sh`

**Files:**
- Create: `tools/reply-resolve.sh`

**Spec sections:** CLI contract, Internal flow.

- [ ] **Step 1: Create the `tools/` directory and the script file with the full implementation**

The script implements the five-phase flow from the spec's "Internal flow" section (arg parsing → preflight stdin validation → id-map fetch → per-line processing → final summary). Write the complete file at `tools/reply-resolve.sh` with these exact contents:

```bash
#!/usr/bin/env bash
#
# tools/reply-resolve.sh — batch reply+resolve for Copilot PR review threads
#
# Reads NDJSON on stdin (one {comment_id, body} per line), replies to each
# comment via REST, resolves the corresponding thread via GraphQL, and emits
# per-line status as NDJSON on stdout plus human progress on stderr.
#
# Dependencies: bash, gh (authenticated), jq. Same stack the skill's other
# snippets already assume. See tools/README.md for usage.
#
# Exit codes:
#   0 — every per-thread operation succeeded
#   1 — at least one per-thread failure, but the batch ran to completion
#   2 — preflight validation error (no HTTP calls made)
#   3 — precondition failure that aborts the batch before per-thread work

set -euo pipefail

# --- Arg parsing & validation (phase 1) ---
#
# We accept --repo OWNER/NAME, --pr N, --sha HASH (optional), --dry-run
# (optional), --help. Required flags and format checks fail at preflight
# (exit 2) so callers see problems before any HTTP attempt.

usage() {
    cat >&2 <<EOF
Usage: tools/reply-resolve.sh --repo <owner>/<repo> --pr <N> [--sha <hash>] [--dry-run]

Batches reply+resolve for Copilot PR review threads. Reads NDJSON on stdin
(one {"comment_id": <int>, "body": "<str>"} per line), replies to each
comment and resolves the thread. See tools/README.md for full usage.

Flags:
  --repo     Required. Target repo as owner/name (e.g. acme/widgets).
  --pr       Required. PR number (integer).
  --sha      Optional. When set, substitutes \${SHA} in reply bodies before
             posting. Required if any body contains \${SHA}.
  --dry-run  Optional. Performs preflight + id-map fetch + substitution +
             thread lookup, but makes no write calls. Useful for verifying
             input before a real run.
  --help     Print this help and exit.
EOF
    exit 0
}

REPO=""
PR_NUM=""
SHA=""
DRY_RUN=0

while [ $# -gt 0 ]; do
    case "$1" in
        --repo) REPO="${2:-}"; shift 2 ;;
        --pr) PR_NUM="${2:-}"; shift 2 ;;
        --sha) SHA="${2:-}"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        --help|-h) usage ;;
        *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
    esac
done

# Required-flag check.
if [ -z "$REPO" ] || [ -z "$PR_NUM" ]; then
    echo "ERROR: --repo and --pr are required. Run with --help for usage." >&2
    exit 2
fi

# --pr must be an integer. Validate here (not in GraphQL) so the caller
# gets a targeted message instead of a downstream type-coercion error.
if ! [[ "$PR_NUM" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --pr must be an integer, got: '$PR_NUM'" >&2
    exit 2
fi

# --repo must be owner/name form with exactly one slash. Split into OWNER/
# NAME for the GraphQL query which takes them as separate fields.
if ! [[ "$REPO" =~ ^[^/]+/[^/]+$ ]]; then
    echo "ERROR: --repo must be in 'owner/repo' form, got: '$REPO'" >&2
    exit 2
fi
OWNER="${REPO%/*}"
NAME="${REPO#*/}"

# --- Buffer stdin to a temp file (phase 1 cont'd) ---
#
# Command substitution ($(cat)) strips trailing newlines and holds the whole
# batch in a shell variable. A temp file avoids both problems and lets us
# re-read the input across preflight + per-thread phases with consistent
# line numbering.
INPUT_FILE=$(mktemp)
trap 'rm -f "$INPUT_FILE"' EXIT
cat > "$INPUT_FILE"

# --- Preflight stdin validation (phase 2 — no HTTP yet) ---
#
# Every exit 2 path lives here. Parsing each line with jq catches malformed
# JSON and missing/mistyped fields; the ${SHA} check catches a body that
# references the template variable without --sha being supplied (which
# would otherwise land a raw '${SHA}' in a real PR comment).

LINE_NUM=0
while IFS= read -r LINE || [ -n "$LINE" ]; do
    LINE_NUM=$((LINE_NUM + 1))
    # Skip blank lines — tolerant of trailing newlines in heredocs.
    [ -z "$LINE" ] && continue

    # jq -e exits non-zero if the filter fails (e.g., the expected fields
    # aren't present with the expected types). We only care about the exit
    # status at this stage.
    if ! echo "$LINE" | jq -e '.comment_id | numbers' >/dev/null 2>&1; then
        echo "ERROR: line $LINE_NUM: malformed NDJSON or missing/non-integer comment_id" >&2
        exit 2
    fi
    if ! echo "$LINE" | jq -e '.body | strings' >/dev/null 2>&1; then
        echo "ERROR: line $LINE_NUM: malformed NDJSON or missing/non-string body" >&2
        exit 2
    fi

    # If any body references ${SHA}, --sha must have been supplied.
    BODY=$(echo "$LINE" | jq -r '.body')
    if [ -z "$SHA" ] && [[ "$BODY" == *'${SHA}'* ]]; then
        echo "ERROR: line $LINE_NUM: body references \${SHA} but --sha wasn't provided" >&2
        exit 2
    fi
done < "$INPUT_FILE"

# --- Fetch the id-map (phase 3 — first HTTP call) ---
#
# One GraphQL call fetches every review thread's ID plus the databaseId of
# its opener comment. We build a JSON object mapping comment_id -> thread_id
# so per-line lookup is a single jq call per thread, not a fresh GraphQL
# query per thread.
#
# reviewThreads(first: 100) caps the fetch. PRs with >100 threads trip the
# guard below and exit 3 rather than silently missing threads.

ID_MAP_JSON=$(gh api graphql \
    -f query='
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
        }' \
    -F owner="$OWNER" \
    -F name="$NAME" \
    -F number="$PR_NUM" 2>&1) || {
    echo "ERROR: id-map GraphQL query failed: $ID_MAP_JSON" >&2
    exit 3
}

TOTAL_THREADS=$(echo "$ID_MAP_JSON" | jq -r '.data.repository.pullRequest.reviewThreads.totalCount')
if [ "$TOTAL_THREADS" -gt 100 ]; then
    echo "ERROR: PR has $TOTAL_THREADS threads; v1 of this script doesn't paginate. File an issue if you hit this." >&2
    exit 3
fi

# Transform nodes into { "<comment_id>": "<thread_id>", ... }. The map keys
# are stringified integers; lookup below uses --arg (string) to match.
ID_MAP=$(echo "$ID_MAP_JSON" | jq '
    .data.repository.pullRequest.reviewThreads.nodes
    | map({ (.comments.nodes[0].databaseId | tostring): .id })
    | add // {}
')

# --- Per-line processing loop (phase 4) ---
#
# For each input line: substitute ${SHA} if applicable, look up the thread
# ID, then either print a dry-run status or attempt reply->resolve. Failures
# within a thread (reply or resolve) emit error/partial status and continue
# the batch.

SUCCESS=0
FAIL=0
LINE_NUM=0

while IFS= read -r LINE || [ -n "$LINE" ]; do
    LINE_NUM=$((LINE_NUM + 1))
    [ -z "$LINE" ] && continue

    COMMENT_ID=$(echo "$LINE" | jq -r '.comment_id')
    BODY=$(echo "$LINE" | jq -r '.body')

    # ${SHA} substitution happens per-line so the emitted 'body' in the
    # dry-run status reflects exactly what would be posted.
    if [ -n "$SHA" ]; then
        BODY="${BODY//\$\{SHA\}/$SHA}"
    fi

    # Thread-id lookup. --arg passes the comment_id as a JSON string; the
    # map keys are strings too, so .[$id] finds the thread or yields empty.
    THREAD_ID=$(echo "$ID_MAP" | jq -r --arg id "$COMMENT_ID" '.[$id] // empty')

    if [ -z "$THREAD_ID" ]; then
        jq -cn --argjson cid "$COMMENT_ID" \
            '{comment_id: $cid, thread_id: null, reply_id: null, resolved: false, status: "error", error: "no thread found for comment \($cid | tostring)"}'
        echo "✗ $COMMENT_ID no thread found" >&2
        FAIL=$((FAIL + 1))
        continue
    fi

    if [ "$DRY_RUN" -eq 1 ]; then
        jq -cn --argjson cid "$COMMENT_ID" --arg tid "$THREAD_ID" --arg body "$BODY" \
            '{comment_id: $cid, thread_id: $tid, reply_id: null, resolved: false, status: "dry_run", body: $body}'
        echo "→ $COMMENT_ID dry-run matched $THREAD_ID" >&2
        SUCCESS=$((SUCCESS + 1))
        continue
    fi

    # Phase 4a: reply via REST. Capture the returned comment id (reply_id)
    # on success. Failure emits status="error" and skips the resolve step.
    REPLY_OUTPUT=$(gh api "repos/$REPO/pulls/$PR_NUM/comments/$COMMENT_ID/replies" -f body="$BODY" 2>&1) || {
        jq -cn --argjson cid "$COMMENT_ID" --arg tid "$THREAD_ID" --arg err "$REPLY_OUTPUT" \
            '{comment_id: $cid, thread_id: $tid, reply_id: null, resolved: false, status: "error", error: ("reply POST failed: " + $err)}'
        echo "✗ $COMMENT_ID reply failed: $REPLY_OUTPUT" >&2
        FAIL=$((FAIL + 1))
        continue
    }
    REPLY_ID=$(echo "$REPLY_OUTPUT" | jq -r '.id')

    # Phase 4b: resolve via GraphQL. Reply already landed, so a resolve
    # failure emits status="partial" (replied-but-unresolved, the safe
    # fallback) rather than "error".
    RESOLVE_OUTPUT=$(gh api graphql \
        -f query='mutation($t: ID!) { resolveReviewThread(input: {threadId: $t}) { thread { id isResolved } } }' \
        -f t="$THREAD_ID" 2>&1) || {
        jq -cn --argjson cid "$COMMENT_ID" --arg tid "$THREAD_ID" --argjson rid "$REPLY_ID" --arg err "$RESOLVE_OUTPUT" \
            '{comment_id: $cid, thread_id: $tid, reply_id: $rid, resolved: false, status: "partial", error: ("resolve mutation failed: " + $err)}'
        echo "⚠ $COMMENT_ID replied but resolve failed: $RESOLVE_OUTPUT" >&2
        FAIL=$((FAIL + 1))
        continue
    }

    jq -cn --argjson cid "$COMMENT_ID" --arg tid "$THREAD_ID" --argjson rid "$REPLY_ID" \
        '{comment_id: $cid, thread_id: $tid, reply_id: $rid, resolved: true, status: "ok"}'
    echo "✓ $COMMENT_ID replied+resolved" >&2
    SUCCESS=$((SUCCESS + 1))
done < "$INPUT_FILE"

# --- Final summary (phase 5) ---
#
# Total on stderr so it doesn't pollute the machine-readable stdout stream.
# Exit 1 if any per-thread operation failed (covers both "error" and
# "partial"), 0 otherwise.

TOTAL=$((SUCCESS + FAIL))
echo "$SUCCESS/$TOTAL succeeded, $FAIL failed" >&2

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
```

Use the Write tool with the exact content above. Do NOT add additional flags, tests, or features beyond what the spec calls out — the spec explicitly scopes out retries, parallelism, pagination, and unit tests.

- [ ] **Step 2: Make the script executable**

Run:

```bash
chmod +x tools/reply-resolve.sh
```

Verify:

```bash
ls -l tools/reply-resolve.sh
```

Expected output: the permissions string starts with `-rwxr-xr-x` (or at least has `x` bits for user/group/other — e.g. `755`).

- [ ] **Step 3: Sanity-check the script parses and runs `--help`**

Run:

```bash
bash -n tools/reply-resolve.sh
./tools/reply-resolve.sh --help
```

Expected:
- `bash -n` exits 0 with no output (clean syntax check).
- `--help` prints the Usage block and exits 0. The Usage block must mention `--repo`, `--pr`, `--sha`, `--dry-run`, `--help`.

If either fails, fix the script inline and re-run both commands before continuing.

- [ ] **Step 4: Sanity-check arg validation without making HTTP calls**

Run each of these and verify the expected exit code and stderr line:

```bash
# Missing required flags → exit 2
./tools/reply-resolve.sh < /dev/null; echo "exit=$?"
# Expected stderr: "ERROR: --repo and --pr are required...", exit=2

# Malformed --repo → exit 2
./tools/reply-resolve.sh --repo notaslug --pr 1 < /dev/null; echo "exit=$?"
# Expected stderr: "ERROR: --repo must be in 'owner/repo' form, got: 'notaslug'", exit=2

# Non-integer --pr → exit 2
./tools/reply-resolve.sh --repo foo/bar --pr abc < /dev/null; echo "exit=$?"
# Expected stderr: "ERROR: --pr must be an integer, got: 'abc'", exit=2

# Malformed NDJSON line → exit 2
echo 'not json' | ./tools/reply-resolve.sh --repo foo/bar --pr 1; echo "exit=$?"
# Expected stderr: "ERROR: line 1: malformed NDJSON or missing/non-integer comment_id", exit=2

# ${SHA} referenced but --sha missing → exit 2
echo '{"comment_id": 1, "body": "Fixed in ${SHA}"}' | ./tools/reply-resolve.sh --repo foo/bar --pr 1; echo "exit=$?"
# Expected stderr: "ERROR: line 1: body references ${SHA} but --sha wasn't provided", exit=2
```

Each case MUST print `exit=2`. If any case returns a different exit code or message, fix the script and re-run. These validations are entirely offline — they exercise the preflight without any `gh api` call.

- [ ] **Step 5: Commit**

```bash
git add tools/reply-resolve.sh
git commit -m "feat(tools): reply-resolve.sh — batch reply+resolve for Copilot review threads

First real code in the skill repo. Implements the spec merged at
b941359 (PR #18): a bash helper that takes NDJSON on stdin (one
{comment_id, body} per line), fetches the REST-id -> GraphQL-thread-id
map once per PR via a single GraphQL call, then per-line replies +
resolves each thread.

Five-phase flow matches the spec's Internal flow section:
  1. Arg parsing + --repo/--pr validation
  2. Preflight stdin validation (jq-parse each line, \${SHA}/--sha check)
  3. Id-map GraphQL fetch (exit 3 on failure or >100 threads)
  4. Per-line reply -> resolve loop, best-effort sequential
  5. Final summary + exit 0/1

Output contract: NDJSON status per line on stdout with one of four
status values (ok | partial | error | dry_run); human progress +
summary on stderr. Exit codes 0/1/2/3 per the spec.

Dependencies: bash, gh, jq — same stack the existing snippets in
references/graphql-snippets.md already use. No unit test harness;
the spec explicitly scopes tests out in favor of manual smoke + the
Copilot review loop on this PR."
```

---

## Task 2: Create `tools/README.md`

**Files:**
- Create: `tools/README.md`

**Spec section:** "Example usage" + the Windows invocation note from the spec's "Out of scope" bullet.

- [ ] **Step 1: Write the README**

Write `tools/README.md` with these exact contents:

````markdown
# `tools/`

Helper scripts for the `github-pr-review-loop` skill. All scripts assume
`bash`, `gh`, and `jq` — the same stack the skill's inline snippets (in
`skills/github-pr-review-loop/references/graphql-snippets.md`) already use.

## `reply-resolve.sh` — batched reply + resolve

Batches the reply-and-resolve roundtrip for Copilot PR review threads.
Takes NDJSON on stdin, one `{comment_id, body}` per line; replies to each
comment and resolves the corresponding thread; emits per-line status as
NDJSON on stdout and human progress on stderr.

Replaces the hand-rolled boilerplate of separately mapping REST comment
IDs to GraphQL thread IDs, POSTing each reply, and mutating each resolve.

### Invocation

```bash
# Set env vars first so the snippet is copy-paste-safe (angle-bracket
# placeholders like <N> are I/O redirection tokens in bash/zsh; quote
# them on the RHS).
REPO="<owner>/<repo>"    # e.g. qubitrenegade/github-pr-review-loop
PR_NUM="<N>"             # e.g. 42
SHA="<hash>"             # optional, omit if no ${SHA} in any body

# Basic invocation (required flags only)
tools/reply-resolve.sh --repo "$REPO" --pr "$PR_NUM" < input.ndjson

# With optional flags: --sha enables ${SHA} templating; --dry-run
# performs read-only id-map fetch + substitution + thread-id lookup,
# but makes no write calls (no reply POST, no resolve mutation).
tools/reply-resolve.sh --repo "$REPO" --pr "$PR_NUM" --sha "$SHA" --dry-run < input.ndjson
```

### Flags

| Flag | Required | Description |
|------|----------|-------------|
| `--repo <owner>/<repo>` | yes | Target repo slug. Validated at preflight. |
| `--pr <N>` | yes | PR number (integer). Validated at preflight. |
| `--sha <hash>` | no | Substitutes `${SHA}` in reply bodies before posting. Required if any body contains `${SHA}`. |
| `--dry-run` | no | Simulates a run: preflight + id-map fetch + substitution + thread lookup, no writes. |
| `--help` | no | Print usage and exit. |

### Input — NDJSON on stdin

Each line is a standalone JSON object with exactly two fields:

- `comment_id` (integer) — the thread opener's REST comment ID (top-level Copilot inline comment, NOT a reply). The preflight id-map only contains openers; supplying a reply's ID will fail the thread-id lookup and emit a per-line error.
- `body` (string) — the reply text. May reference `${SHA}` for tool-side substitution. Literal newlines inside `body` aren't valid NDJSON; use JSON-escaped `\n` or generate the JSON programmatically (e.g. `jq -Rsc '{comment_id: 12345, body: .}' < body.txt`).

Example stdin:

```json
{"comment_id": 12345, "body": "Fixed in `${SHA}` — commands_dir is Path"}
{"comment_id": 67890, "body": "Fixed in `${SHA}` — same fix applied"}
```

### Output

- **stdout** — NDJSON status per input line, in input order. The `status` field takes one of four values:
  - `"ok"` — reply POST succeeded AND resolve mutation succeeded. `reply_id` populated, `resolved: true`, no `error` field.
  - `"partial"` — reply POST succeeded but resolve mutation failed. `reply_id` populated, `resolved: false`, `error` describes the resolve failure. The thread ends up replied-but-unresolved (a safe fallback).
  - `"error"` — reply POST failed (or the thread-id lookup found no thread for this `comment_id`). `reply_id: null`, `resolved: false`, `error` describes the failure. Resolve is not attempted when reply fails.
  - `"dry_run"` — only emitted when `--dry-run` is set. `thread_id` populated (matched thread), resolved body in an additional `body` field, no write calls made.

- **stderr** — human-readable per-line progress (`✓`/`⚠`/`✗`/`→`) and a final `X/Y succeeded, Z failed` summary.

### Exit codes

- `0` — every per-thread operation succeeded.
- `1` — at least one per-thread failure (`error` or `partial`), but the batch ran to completion.
- `2` — preflight validation error (bad flag, malformed NDJSON, `${SHA}` without `--sha`). No HTTP calls made.
- `3` — precondition failure before per-thread work (id-map GraphQL call failed, or PR has >100 threads — v1 doesn't paginate).

### Example — heredoc

```bash
SHA=$(git rev-parse --short HEAD)
tools/reply-resolve.sh --repo qubitrenegade/github-pr-review-loop --pr 42 --sha "$SHA" <<'EOF'
{"comment_id": 3106483445, "body": "Fixed in `${SHA}` — commands_dir is a Path, not a string."}
{"comment_id": 3106483456, "body": "Fixed in `${SHA}` — same fix applied."}
EOF
```

Quoted heredoc delimiter (`<<'EOF'`) prevents the shell from expanding `${SHA}` before the script sees it — the script does the substitution itself so heredoc and file-input paths behave identically.

### Example — file input

```bash
cat replies.ndjson | tools/reply-resolve.sh --repo qubitrenegade/github-pr-review-loop --pr 42 --sha abc1234
```

### Example — dry-run before the real call

```bash
tools/reply-resolve.sh --repo qubitrenegade/github-pr-review-loop --pr 42 --sha abc1234 --dry-run < replies.ndjson
```

The dry-run will confirm: the id-map lookup matches every `comment_id` to a thread, `${SHA}` substitutions render as expected, and no line fails preflight. Then drop `--dry-run` to actually post.

### Windows

The script is bash. On Windows, invoke via Git Bash or WSL. Git for Windows installs bash at `C:\Program Files\Git\bin\bash.exe`; if bash isn't on PATH, run via the full path:

```powershell
& "C:\Program Files\Git\bin\bash.exe" tools/reply-resolve.sh --repo "$REPO" --pr "$PR_NUM"
```

### Limitations

- PRs with more than 100 review threads are not supported in v1 (the script exits 3 rather than silently paginating).
- No retries on transient `gh` failures (`gh` has reasonable defaults; permanent failures don't benefit from retry).
- No parallelism — sequential per-thread keeps error output sane and respects GitHub's rate posture.
- No PowerShell port; see the Windows note above.
````

Use the Write tool with the exact content above.

- [ ] **Step 2: Verify the README reads cleanly**

Run:

```bash
head -20 tools/README.md
grep -n "^## " tools/README.md
```

Expected:
- `head -20` shows the title, intro paragraph, section heading for `reply-resolve.sh`.
- `grep` shows the section hierarchy: `## reply-resolve.sh` as the top-level helper section, with sub-sections for Invocation, Flags, Input, Output, Exit codes, Examples (heredoc/file/dry-run), Windows, Limitations.

- [ ] **Step 3: Commit**

```bash
git add tools/README.md
git commit -m "docs(tools): README for reply-resolve.sh

Per spec docs/superpowers/specs/2026-04-22-reply-resolve-helper-design.md
(Example usage section + Windows invocation note). Documents the CLI
contract (flags, stdin format, stdout/stderr output, exit codes) plus
heredoc/file/dry-run example patterns and the Git-Bash invocation path
for Windows users without bash on PATH."
```

---

## Task 3: Apply four doc-pointer edits

**Files:**
- Modify: `skills/github-pr-review-loop/SKILL.md`
- Modify: `skills/github-pr-review-loop/references/triage-patterns.md`
- Modify: `skills/github-pr-review-loop/references/graphql-snippets.md`
- Modify: `README.md` (repo root)

**Spec sections:** "SKILL.md pointer", "triage-patterns.md pointer", "graphql-snippets.md additions", "README.md (root) update".

- [ ] **Step 1: Verify current state of all four target locations**

Run:

```bash
# SKILL.md step 5 — the pointer will be appended here
grep -n "Resolve each thread after replying" skills/github-pr-review-loop/SKILL.md

# triage-patterns.md Batching section — the pointer goes before "Sweep before you push"
grep -n "^### Sweep before you push" skills/github-pr-review-loop/references/triage-patterns.md

# graphql-snippets.md — new section goes between "Reply to a specific inline comment" and "List review threads with resolved state"
grep -n "^## Reply to a specific inline comment" skills/github-pr-review-loop/references/graphql-snippets.md
grep -n "^## List review threads with resolved state" skills/github-pr-review-loop/references/graphql-snippets.md

# graphql-snippets.md Contents TOC — new entry between the two related lines
grep -n "^- Reply to a specific inline comment" skills/github-pr-review-loop/references/graphql-snippets.md
grep -n "^- List review threads with resolved state" skills/github-pr-review-loop/references/graphql-snippets.md

# README.md Structure block — where we add a tools/ line
grep -n "^## Structure" README.md
grep -n "^└── github-pr-review-loop/" README.md
```

Expected: each grep returns at least one matching line. If any returns 0 matches, stop and investigate before applying edits.

- [ ] **Step 2: Edit 1 — Append pointer sentence to SKILL.md "The loop" step 5**

Per spec "SKILL.md pointer". The current step 5 reads:

```
5. Post inline replies with commit SHAs / empirical dismissals / follow-up issue links. Resolve each thread after replying (**except Acknowledge threads, which stay unresolved pending maintainer decision — see "After replying, resolve the conversation"**).
```

Append this sentence after the existing text of step 5 (inside the same list item, on a new line immediately below — part of the same numbered item, not a new item):

```
   For batches of more than two threads per round, `tools/reply-resolve.sh` handles the reply+resolve roundtrip — see `tools/README.md`.
```

(The three-space indent keeps the sentence part of list item 5 in Markdown rendering.)

Use the Edit tool. The `old_string` should be the full existing step-5 line; the `new_string` should be the full existing step-5 line plus a newline plus three-space-indented pointer sentence.

- [ ] **Step 3: Edit 2 — Insert pointer paragraph in triage-patterns.md Batching section**

Per spec "triage-patterns.md pointer". Find the `### Sweep before you push` subsection inside `## Batching multiple findings into one push`. Immediately BEFORE the `### Sweep before you push` heading line (and with a blank line between the new paragraph and the heading), insert this paragraph:

```
For the reply-and-resolve step specifically (processing many threads in one round), `tools/reply-resolve.sh` at the repo root takes NDJSON on stdin and handles the full reply+resolve transaction per thread. See `tools/README.md` for usage.
```

Use the Edit tool with the `### Sweep before you push` heading as part of `old_string` so the insertion point is unambiguous. `new_string` should be the new paragraph, a blank line, then the heading.

- [ ] **Step 4: Edit 3 — Add graphql-snippets.md Contents entry and new section**

Per spec "graphql-snippets.md additions".

**Contents entry:** In the `## Contents` bullet list, insert a new line between `- Reply to a specific inline comment` and `- List review threads with resolved state`:

```
- Batching reply + resolve with `tools/reply-resolve.sh`
```

**New section:** Insert a new `## Batching reply + resolve with `tools/reply-resolve.sh`` section between the existing `## Reply to a specific inline comment` section and the existing `## List review threads with resolved state` section. The new section body is:

````markdown
## Batching reply + resolve with `tools/reply-resolve.sh`

The raw `repos/$REPO/pulls/$PR_NUM/comments/$COMMENT_ID/replies` POST and `resolveReviewThread` mutation snippets above are the primitives. For batches (more than two threads per round), `tools/reply-resolve.sh` at the repo root wraps both into a single per-thread transaction, handles the REST `comment_id` → GraphQL `thread_id` lookup internally, and supports `${SHA}` templating. See `tools/README.md` for usage.
````

Use the Edit tool once for the Contents entry, and a second Edit tool invocation for the new section body. The section body's `old_string` should include the `## List review threads with resolved state` heading line so the insertion is anchored; the `new_string` is the new section body, a blank line, then the `## List review threads with resolved state` heading.

- [ ] **Step 5: Edit 4 — Add `tools/` line to README.md Structure block**

Per spec "README.md (root) update". The current Structure block shows the `skills/` directory tree. Extend it so a second block documents `tools/`. Find this existing block (around line 134-144):

```
## Structure

```
skills/
└── github-pr-review-loop/
    ├── SKILL.md                            # Core prompt (loaded when invoked)
    └── references/
        ├── triage-patterns.md              # apply / dismiss / clarify / defer templates + resolve discipline
        ├── graphql-snippets.md             # requestReviews + comment queries + thread resolution + bot-ID discovery
        ├── stop-conditions.md              # when to stop chasing (incl. "CI must be green" precondition)
        ├── wave-orchestration.md           # multi-PR parallel scaling
        └── case-study-clickwork-1.0.md     # concrete 24-issue run
```
```

Append this second code block immediately after the `skills/` tree (still inside the Structure section, before "References load on demand..."):

```
tools/
├── README.md              # Usage for helper scripts below
└── reply-resolve.sh       # Batched reply+resolve for Copilot PR review threads
```

Use the Edit tool. `old_string` should be the closing ` ``` ` of the `skills/` tree plus the next "References load on demand..." sentence; `new_string` adds the `tools/` block in between.

- [ ] **Step 6: Verify all four edits landed**

Run:

```bash
grep -n "tools/reply-resolve.sh" skills/github-pr-review-loop/SKILL.md
grep -n "tools/reply-resolve.sh" skills/github-pr-review-loop/references/triage-patterns.md
grep -n "^## Batching reply + resolve" skills/github-pr-review-loop/references/graphql-snippets.md
grep -n "^- Batching reply + resolve" skills/github-pr-review-loop/references/graphql-snippets.md
grep -n "^└── reply-resolve.sh" README.md
```

Expected: each grep returns at least one matching line. Zero matches means an edit didn't land.

- [ ] **Step 7: Commit**

```bash
git add skills/github-pr-review-loop/SKILL.md \
        skills/github-pr-review-loop/references/triage-patterns.md \
        skills/github-pr-review-loop/references/graphql-snippets.md \
        README.md
git commit -m "docs: pointer edits for reply-resolve.sh across skill docs

Per spec docs/superpowers/specs/2026-04-22-reply-resolve-helper-design.md:

- SKILL.md step 5: appended pointer to tools/reply-resolve.sh for batches of >2 threads per round.
- triage-patterns.md Batching section: added a paragraph before 'Sweep before you push' pointing at the helper for the reply-and-resolve step.
- graphql-snippets.md: added Contents entry + new section between 'Reply to a specific inline comment' and 'List review threads with resolved state'.
- README.md Structure block: added a tools/ tree block documenting README.md + reply-resolve.sh."
```

---

## Task 4: Manual smoke test (main session)

**Scope:** Main session, not subagent — needs access to live PR data and judgment about dry-run output.

- [ ] **Step 1: Find a target PR with unresolved Copilot threads**

Any PR from this batch that still has unresolved threads works; a simpler option is to create a scratch PR with a trivial diff and let Copilot comment on it.

Identify a target via:

```bash
gh pr list --repo qubitrenegade/github-pr-review-loop --state open --json number,title
```

If no open PR with unresolved threads is available, skip to Step 3 (help-check + preflight-only paths); the manual smoke test has already been exercised offline in Task 1 Step 4.

- [ ] **Step 2: Dry-run against the target PR**

Pick a PR number `$PR_NUM` with at least one unresolved Copilot thread, look up a `comment_id` from that thread (any thread-opener comment), and run:

```bash
PR_NUM=<N>
COMMENT_ID=<id from the target PR>
SHA=$(git rev-parse --short HEAD)

echo "{\"comment_id\": $COMMENT_ID, \"body\": \"Smoke test in \`\${SHA}\`.\"}" \
  | ./tools/reply-resolve.sh --repo qubitrenegade/github-pr-review-loop --pr $PR_NUM --sha "$SHA" --dry-run
```

Expected:
- exit 0.
- stderr shows `→ $COMMENT_ID dry-run matched PRRT_...` and `1/1 succeeded, 0 failed`.
- stdout shows a single NDJSON line with `"status":"dry_run"`, `"thread_id":"PRRT_..."`, and the substituted body.

If the thread-id lookup fails (stdout shows `"status":"error"` and exit 1), either the `comment_id` wasn't the thread opener (try another) or the id-map has a bug — in that case stop and investigate.

- [ ] **Step 3: Verify help + preflight error paths one more time against the final script**

Re-run the Task 1 Step 4 error-path checks to confirm nothing regressed after the file received doc-related edits upstream (they shouldn't touch the script, but confirm):

```bash
./tools/reply-resolve.sh --help; echo "exit=$?"
./tools/reply-resolve.sh < /dev/null; echo "exit=$?"
echo '{"comment_id": 1, "body": "Fixed in ${SHA}"}' | ./tools/reply-resolve.sh --repo foo/bar --pr 1; echo "exit=$?"
```

Expected: `--help` exits 0; missing-flags exits 2; `${SHA}`-without-`--sha` exits 2.

- [ ] **Step 4: Document the smoke test result**

If Step 2 succeeded, nothing further needed; the smoke test is the record.

If Step 2 failed, create a small section in `tools/README.md` under "Limitations" describing the failure mode and file a follow-up issue. Don't merge with a broken helper.

---

## Task 5: Open PR + run Copilot review loop (main session)

**Scope:** Main session. Review loop needs conversational decision-making that doesn't delegate.

- [ ] **Step 1: Push branch**

```bash
git push -u origin docs/implement-reply-resolve-helper-4
```

- [ ] **Step 2: Open PR**

```bash
gh pr create --title "feat: reply-resolve.sh + tools/ — batch reply+resolve (#4)" --body "$(cat <<'EOF'
## Summary

Implementation PR for the spec merged at b941359 (PR #18). Closes issue #4.

First real code change in the skill repo. Ships a bash helper that batches the reply+resolve roundtrip for Copilot PR review threads — taking NDJSON on stdin, replying to each comment, and resolving each thread in a single per-thread transaction.

## Files

**New:**
- `tools/reply-resolve.sh` — the helper (~180 lines with teaching comments). Five-phase flow: arg parsing → preflight stdin validation → id-map GraphQL fetch → per-line reply+resolve loop → final summary.
- `tools/README.md` — usage, flag reference, stdout/stderr/exit-code contract, heredoc+file+dry-run examples, Windows invocation via Git Bash.

**Pointer edits:**
- `skills/github-pr-review-loop/SKILL.md` step 5: appended pointer to the helper for batches of >2 threads per round.
- `skills/github-pr-review-loop/references/triage-patterns.md` Batching section: paragraph pointing at the helper for the reply-and-resolve step.
- `skills/github-pr-review-loop/references/graphql-snippets.md`: Contents entry + new section between the reply and thread-resolution primitives.
- `README.md` Structure block: added a `tools/` subtree.

**Plan doc:**
- `docs/superpowers/plans/2026-04-22-reply-resolve-helper-implementation.md` — the plan followed to make these edits.

## Behavior highlights (from the spec)

- **Stdin: NDJSON** — `{comment_id, body}` per line. Thread-opener `comment_id` only (replies' IDs won't match the id-map).
- **\`--sha\` template substitution** — tool-side, not shell-side. If a body references \`\${SHA}\` without \`--sha\`, preflight exits 2 before any HTTP.
- **Best-effort sequential** — one thread's failure doesn't abort the batch. Reply first, then resolve.
- **Dual output** — NDJSON status per line on stdout (four values: \`ok\` / \`partial\` / \`error\` / \`dry_run\`); human-readable progress + summary on stderr.
- **Exit codes** — \`0\` all succeeded; \`1\` any per-thread failure; \`2\` preflight validation; \`3\` precondition failure (id-map or >100 threads).

## Out of scope (per the spec)

- PowerShell port, GraphQL pagination for >100 threads, parallelism, retries, unit-test harness. Each is an additive follow-up if demand emerges.

## Test plan

- [x] Preflight validation smoke-tested offline during implementation (malformed JSON, missing flags, \`\${SHA}\`-without-\`--sha\`, etc.).
- [ ] Dry-run against a live PR with a known thread-opener comment_id → confirms id-map lookup + substitution produce correct \`dry_run\` stdout.
- [ ] Copilot review loop on this PR (dogfood). This very PR could be one of the first batches the helper handles.
- [ ] Standing merge authorization in effect: merge when Copilot converges cleanly AND no open questions.

Closes #4
Spec: \`docs/superpowers/specs/2026-04-22-reply-resolve-helper-design.md\`
Plan: \`docs/superpowers/plans/2026-04-22-reply-resolve-helper-implementation.md\`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Capture the PR number printed by `gh pr create`.

- [ ] **Step 3: Request Copilot review**

```bash
REPO="qubitrenegade/github-pr-review-loop"
PR_NUM="<the-number-gh-pr-create-just-printed>"
BOT_ID="BOT_kgDOCnlnWA"
PR_ID=$(gh pr view "$PR_NUM" --repo "$REPO" --json id --jq .id)
gh api graphql -f query='
  mutation($prId: ID!, $botId: ID!) {
    requestReviews(input: {pullRequestId: $prId, botIds: [$botId]}) {
      pullRequest { number }
    }
  }' -f prId="$PR_ID" -f botId="$BOT_ID"
```

- [ ] **Step 4: Run the review loop**

Handoff to the `github-pr-review-loop` skill's normal drill. Standing merge authorization is in effect: merge when Copilot comes back clean AND no open questions. Any question, dismissal needing judgment, or surprise → stop and flag.

When clean: squash-merge. The `Closes #4` keyword will auto-close the issue.

---

## Self-review notes

- **Spec coverage:**
  - CLI contract → Task 1 (flag parsing, validation, `--sha`/`--dry-run` semantics).
  - Internal flow (phases 1-5) → Task 1 Step 1 (the script body implements each phase in order).
  - NDJSON input format → Task 1 (preflight validation) + Task 2 (README).
  - Output contract (NDJSON statuses, stderr, exit codes) → Task 1 + Task 2.
  - "SKILL.md pointer", "triage-patterns.md pointer", "graphql-snippets.md additions", "README.md (root) update" → Task 3 (edits 1-4).
  - Verification section → Task 1 Step 4 (error-path sanity checks) + Task 4 (smoke test).
- **Placeholder scan:** No TBDs. `<owner>/<repo>`, `<N>`, `<hash>`, `<id from the target PR>` are intentional CLI/example placeholders that the caller substitutes.
- **Type consistency:**
  - `tools/reply-resolve.sh` path is used consistently across all tasks and pointer texts.
  - Flag names (`--repo`, `--pr`, `--sha`, `--dry-run`, `--help`) match across the script, README, and commit messages.
  - Exit codes 0/1/2/3 match the spec throughout.
  - Status values (`ok`/`partial`/`error`/`dry_run`) match the spec throughout.
- **Explicitly using `Closes #4` not `Refs #4`** in the PR body and the final implementation commit is out of scope for this plan (the final merge-commit subject line is controlled by the squash-merge UI). But the PR-body `Closes #4` keyword triggers auto-close on merge, which is what we need.
