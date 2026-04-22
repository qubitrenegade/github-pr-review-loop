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
