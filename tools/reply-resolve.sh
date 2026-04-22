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

# --sha, if provided, must look like a git SHA (hex chars). Catches typos
# like '--sha v1.0.0' or an accidental '/' before they land in a body.
if [ -n "$SHA" ] && ! [[ "$SHA" =~ ^[0-9a-fA-F]+$ ]]; then
    echo "ERROR: --sha must be hex (got: '$SHA')" >&2
    exit 2
fi

# --- Buffer stdin to a temp file (phase 1 cont'd) ---
#
# Command substitution ($(cat)) strips trailing newlines and holds the whole
# batch in a shell variable. A temp file avoids both problems and lets us
# re-read the input across preflight + per-thread phases with consistent
# line numbering.
# Portable mktemp: GNU `mktemp` accepts a direct template path; BSD/macOS
# needs `-t`. Try GNU form first, fall back to BSD form.
INPUT_FILE="$(
    mktemp "${TMPDIR:-/tmp}/reply-resolve.XXXXXX" 2>/dev/null \
        || mktemp -t reply-resolve.XXXXXX 2>/dev/null
)" || {
    echo "ERROR: failed to create temporary file" >&2
    exit 2
}
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
    # status at this stage. printf beats echo here because echo on some
    # shells interprets backslash escapes, which would corrupt JSON strings
    # containing "\n" or "\t" before jq sees them.
    # The `select(type == "number" and . == floor)` filter rejects non-
    # integers (e.g. 1.5, 1e3) — REST comment IDs are always integers.
    if ! printf '%s\n' "$LINE" | jq -e '.comment_id | select(type == "number" and . == floor)' >/dev/null 2>&1; then
        echo "ERROR: line $LINE_NUM: malformed NDJSON or missing/non-integer comment_id" >&2
        exit 2
    fi
    if ! printf '%s\n' "$LINE" | jq -e '.body | strings' >/dev/null 2>&1; then
        echo "ERROR: line $LINE_NUM: malformed NDJSON or missing/non-string body" >&2
        exit 2
    fi

    # If any body references ${SHA}, --sha must have been supplied.
    BODY=$(printf '%s\n' "$LINE" | jq -r '.body')
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

# `gh api graphql` can exit 0 while the response body is non-JSON (proxy
# HTML, auth challenge) or a GraphQL error payload (`{"errors": [...]}`) or
# a payload with `.data.repository.pullRequest` null (repo/PR not found).
# Validate the shape before trusting totalCount — downstream `-gt` on a
# non-integer would silently do the wrong thing.
if ! printf '%s\n' "$ID_MAP_JSON" | jq -e . >/dev/null 2>&1; then
    echo "ERROR: id-map response was not valid JSON: $ID_MAP_JSON" >&2
    exit 3
fi
if printf '%s\n' "$ID_MAP_JSON" | jq -e '.errors' >/dev/null 2>&1; then
    echo "ERROR: id-map GraphQL returned errors: $(printf '%s\n' "$ID_MAP_JSON" | jq -c '.errors')" >&2
    exit 3
fi
if ! printf '%s\n' "$ID_MAP_JSON" | jq -e '.data.repository.pullRequest.reviewThreads.totalCount | numbers' >/dev/null 2>&1; then
    echo "ERROR: id-map response missing expected shape (pullRequest or reviewThreads nil). Raw: $ID_MAP_JSON" >&2
    exit 3
fi

TOTAL_THREADS=$(printf '%s\n' "$ID_MAP_JSON" | jq -r '.data.repository.pullRequest.reviewThreads.totalCount')
if [ "$TOTAL_THREADS" -gt 100 ]; then
    echo "ERROR: PR has $TOTAL_THREADS threads; v1 of this script doesn't paginate. File an issue if you hit this." >&2
    exit 3
fi

# Transform nodes into { "<comment_id>": "<thread_id>", ... }. The map keys
# are stringified integers; lookup below uses --arg (string) to match.
ID_MAP=$(printf '%s\n' "$ID_MAP_JSON" | jq '
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

    COMMENT_ID=$(printf '%s\n' "$LINE" | jq -r '.comment_id')
    BODY=$(printf '%s\n' "$LINE" | jq -r '.body')

    # ${SHA} substitution happens per-line so the emitted 'body' in the
    # dry-run status reflects exactly what would be posted.
    if [ -n "$SHA" ]; then
        BODY="${BODY//\$\{SHA\}/$SHA}"
    fi

    # Thread-id lookup. --arg passes the comment_id as a JSON string; the
    # map keys are strings too, so .[$id] finds the thread or yields empty.
    THREAD_ID=$(printf '%s\n' "$ID_MAP" | jq -r --arg id "$COMMENT_ID" '.[$id] // empty')

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
    # jq suffix `|| echo ""` so `set -e` doesn't kill the script if REPLY_OUTPUT
    # isn't JSON at all (e.g., `gh api 2>&1` mixed stderr text into stdout on
    # a transient proxy error). The integer regex below catches both the
    # "jq failed" case and the "jq emitted non-integer" case uniformly.
    REPLY_ID=$(printf '%s\n' "$REPLY_OUTPUT" | jq -r '.id // empty' 2>/dev/null || echo "")

    # Guard: gh exited 0 but the response didn't contain an `id` field.
    # Rare (would indicate API format drift or an HTML error page), but
    # without this check the reply_id would be empty and the jq --argjson
    # call below would fail with an opaque parse error. Emit a clear
    # status="error" instead.
    if ! [[ "$REPLY_ID" =~ ^[0-9]+$ ]]; then
        jq -cn --argjson cid "$COMMENT_ID" --arg tid "$THREAD_ID" --arg err "reply POST succeeded but response lacked an integer 'id' field: $REPLY_OUTPUT" \
            '{comment_id: $cid, thread_id: $tid, reply_id: null, resolved: false, status: "error", error: $err}'
        echo "✗ $COMMENT_ID reply response malformed: $REPLY_OUTPUT" >&2
        FAIL=$((FAIL + 1))
        continue
    fi

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

    # gh exited 0 but GraphQL can still return 200 with `.errors` or with
    # `.data.resolveReviewThread.thread.isResolved != true`. Verify the
    # thread actually resolved before claiming status="ok".
    RESOLVED_FLAG=$(printf '%s\n' "$RESOLVE_OUTPUT" | jq -r '.data.resolveReviewThread.thread.isResolved // false' 2>/dev/null || echo "false")
    if [ "$RESOLVED_FLAG" != "true" ]; then
        jq -cn --argjson cid "$COMMENT_ID" --arg tid "$THREAD_ID" --argjson rid "$REPLY_ID" --arg err "resolve mutation returned 200 but thread.isResolved != true: $RESOLVE_OUTPUT" \
            '{comment_id: $cid, thread_id: $tid, reply_id: $rid, resolved: false, status: "partial", error: $err}'
        echo "⚠ $COMMENT_ID replied but resolve unconfirmed: $RESOLVE_OUTPUT" >&2
        FAIL=$((FAIL + 1))
        continue
    fi

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
