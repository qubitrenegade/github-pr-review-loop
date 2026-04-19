# Triage patterns — apply, dismiss, clarify, defer

Templates and examples for each triage category, plus the evidence
checklist for dismissals and the discipline around resolving threads.

## Contents

- Apply — fix + cite commit SHA
- Dismiss — reply with empirical evidence
- Clarify — ask before guessing
- Defer — out-of-scope but valid, file a follow-up issue
- Resolve the thread after replying
- Evidence checklist (what to run for each claim type)
- Batching multiple findings into one push
- Special cases

## Apply

The finding is real. Fix it, commit, push, reply with the commit SHA.

**Template:**

> Fixed in `<sha>` — <one-sentence description of the fix>.

**Examples (real):**

> Fixed in `bb56bfc` — bumped `__version__` to 1.0.0 in
> src/clickwork/__init__.py. Good catch, this would have broken any
> consumer's `--version` resolution.

> Fixed in `acc31d3` — `_stub_entry_points` now captures
> `importlib.metadata.entry_points` before monkeypatching and forwards
> non-`clickwork.commands` queries through the real impl. Comment also
> updated to match.

The SHA points the reader at the fix without them having to scroll the
diff. Keep the one-sentence description specific enough to match the
finding: "Fixed" alone is low-value; "Fixed typo" on a structural
refactor is misleading.

## Dismiss

The finding is wrong — a hallucination, a stale claim, or a suggestion
that contradicts an intentional design choice. Reply with evidence, not
opinion.

**Template:**

> Dismissing — <one-sentence rationale>. Evidence: <concrete check
> output or file+line reference>.

**Examples (real):**

> Dismissing (hallucination): `docs/LLM_REFERENCE.md` line 184 has
> `## Common Footguns` which renders as anchor `#common-footguns`
> under GitHub-flavored Markdown. The link resolves.

> Reply-dismiss: pre-change state on main was actually
> `clickwork>=0.2.0,<0.3` from PyPI (verified: `git show
> origin/main:tools/pyproject.toml | grep clickwork`). Copilot
> mis-identified the base. PR description updated to match reality.

> Reply-dismiss: both tests call `sender.start()` and use daemon
> threads with a bounded `ready.wait(timeout=5)` + at most one
> `os.kill(os.getpid(), SIGINT)`. If run() raises before spawning the
> child, the sender thread still joins normally because (a) the
> ready-event timeout fires at 5s max, (b) SIGINT is sent once and
> then returns, (c) `thread.daemon = True` means it cannot leak past
> process exit. Teardown risk is bounded at 5s; no unbounded hang.

## Clarify

Genuinely ambiguous finding, or one where acting would require
guessing. Ask before changing code.

**Template:**

> What specifically would <proposed change> mean here? <your
> reading of the current behavior>. <your question>.

**Example:**

> What specifically would "improve the error path" mean here? The
> current `ConfigError` already names the missing key and the file
> path. Are you looking for a structured exception subtype, or a
> different wording in the message, or something else?

Don't use this as a stall — if you have enough to make a decision,
make it. Clarify is for genuine ambiguity.

## Defer

The finding is correct, but fixing it would expand the scope of this
PR beyond what's responsible to ship in one change. File a follow-up
issue capturing the problem, link it in the reply, move on.

**Template:**

> Valid concern — filed as #<N> for a dedicated cycle. Out of scope
> for this PR, which is focused on <current scope>. The proposed
> change would <specific consequence: touch unrelated module /
> require new tests / extend API surface / etc.>.

**When to use Defer instead of Apply:**

- The fix touches code the current PR doesn't otherwise modify.
- The fix requires new tests to be meaningful.
- The fix exposes or changes public API that needs its own design
  discussion.
- The fix is a refactor that would balloon the diff past a
  reviewable size.

**When NOT to use Defer (use Apply instead):**

- The fix is a one-line correction to code the current PR already
  touches.
- The fix is a doc clarification that was obviously missing.
- The finding is a typo, misleading comment, or similar trivial fix
  in a file already in the diff.
- Deferring would leave the merged code actively wrong rather than
  just incomplete.

**Examples (real):**

> Valid concern — filed as #61 for a dedicated 1.0.x cycle. Out of
> scope for this PR, which is focused on the 1.0 public API.
> Sigstore wiring needs its own workflow changes, a cosign keyless
> setup, and verification-doc updates; doing it drive-by would
> extend this release's test surface substantially.

> Filed as #94 — mkdocs-material docs site. Agreed the existing
> `docs/` tree would benefit from a published site; that's a
> dedicated workflow + theme + index page that doesn't belong in a
> release-cut PR.

**The follow-up issue should include:**

- The original Copilot finding (paste or quote it, with PR link).
- Your assessment of why it's valid.
- Rough scope: what files, what tests, what API implications.
- Any prerequisites (e.g. "land after #N before starting this").

Without the issue, `Defer` is indistinguishable from "ignored it".
Filing the issue is what makes the disposition accountable.

## Resolve the thread after replying

Every Copilot inline comment is a "review thread" with its own
`isResolved` state. After you reply — whether with an Apply-SHA, a
Dismissal, a Clarify question the reviewer answered, or a Defer
with linked issue — mark the thread resolved.

**UI path:** the thread shows a "Resolve conversation" button at the
bottom of the thread (next to the reply box). Click it. The thread
collapses and the PR's "unresolved conversations" count drops.

**GraphQL path** (for scripted flow):

```bash
THREAD_ID=<from reviewThreads query>
gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) {
      thread { isResolved }
    }
  }' -f threadId="$THREAD_ID"
```

See [graphql-snippets.md](graphql-snippets.md) for the thread-listing
query that gets you the thread IDs.

**Why resolve matters:**

- The PR's "unresolved conversations" count is a stop-condition
  signal. If it's 0, every thread has been closed-loop — either
  fixed, dismissed with evidence, deferred with issue, or clarified
  and then one of those three. Human reviewers skimming the PR
  can trust this.
- Resolved threads collapse by default in the UI. Unresolved
  threads stay expanded. Scrolling a PR with 30 threads, 28 resolved
  and 2 unresolved, is much less fatiguing than 30 all visible.
- "Resolved" is the equivalent of closing an issue. Orphaned open
  threads rot into ambiguity — was it fixed? was it ignored? —
  and a future maintainer can't tell.

**When NOT to resolve:**

- Before you reply. Resolving silently (no reply) looks dismissive
  and leaves no record of what you decided.
- When you've asked a Clarify question and the reviewer hasn't
  answered yet. Leave it unresolved until they respond.
- When a human reviewer is still active on the thread. Let them
  resolve it themselves; don't stomp on their conversation.

## Evidence checklist

What to run when dismissing each class of claim.

| Claim type | Verification command | Notes |
|---|---|---|
| "Symbol doesn't exist" | `grep -rn 'symbol_name' src/ tests/` | Check the claim's scope — maybe it exists in a file the reviewer didn't scan. |
| "Import would fail" | `python -c "from module import thing; print(thing)"` | Do this in a fresh venv or the project's venv, not wherever your shell landed. |
| "Anchor / link broken" | `grep -n '^## Heading' docs/FILE.md` | GitHub anchors are `#`+lowercased+hyphenated. Verify against rendered GitHub view if unsure. |
| "Test would fail" | Run the test: `pytest path/to/test.py::test_name` | Cite the pass in the reply. If it fails, that's not a dismissal — it's an apply. |
| "Version / pin is wrong" | `git show origin/main:path/to/file` or `grep -nE 'pattern' file` | Resolve against the actual base state, not your reading. |
| "Behavior would surprise" | Run the actual behavior — no need to defend a hypothesis | Usually three lines of `python` clears it up. |
| "Action X will break CI" | Check CI history: `gh run list --branch main --workflow name --limit 5 --json conclusion` | If main shows the same check passing, the claim is specific to the PR. If main is red too, it's pre-existing infra, not a blocker. |

## Batching multiple findings into one push

If a round raises N findings, process all of them before pushing. One
combined commit (or one logical commit per category) keeps the review
thread coherent:

- Read all inline comments in one pass.
- Write triage decisions next to each (apply / dismiss / clarify / defer).
- Apply all the "apply" fixes, group by theme if sensible.
- Commit once (or with semantic boundaries: fix, docs, style).
- **Sweep before you push** (see below).
- Post all replies in one pass.
- Re-request review once.

Pushing a commit for each finding individually multiplies the Copilot
rounds and sends the same diff through N reviews. Wasteful.

### Sweep before you push

When a fix renames a variable, changes a path convention, restructures
a code block, or alters a placeholder style, grep the whole file (and
adjacent files in the same skill/directory) for the **old** name /
path / convention. Copilot will not see the dangling reference as
"the fix is wrong" — it will see it as an independent bug, and you
will chase it next round.

Examples where this matters:

- **Renamed a shell variable** (`REPO` → `OWNER/NAME`). Grep for
  `$REPO`, `\$REPO`, `${REPO}` across every file the refactor
  touched AND every file that imports its conventions.
- **Changed a placeholder quoting style** (`<owner>` → `"<owner>"`).
  Grep for unquoted angle-bracket occurrences in the same section
  AND in any snippets that copy-paste from the style you just
  updated.
- **Renamed a heading, anchor, or file**. Grep for `#old-anchor`
  and for the old filename; fix every reference before pushing.
- **Removed or moved a code block's variable definitions**. Every
  downstream reference to those vars in the same document becomes
  dangling — sweep for them.

Concrete pattern:

```bash
# After your fix commit, before git push
git diff HEAD~1 --name-only | while read f; do
  echo "=== $f ==="
  grep -n 'OLD_NAME\|<old_placeholder>\|#old-anchor' "$f"
done
```

Why this belongs in the loop: late-round findings often cascade from
fixes (round N's fix → round N+1 catches a dangling reference the
fix missed). Each cascade wastes a round. A 60-second sweep before
push prevents the cascade.

Heuristic for when the recursion is done: if TWO consecutive rounds
find zero new issues AND no files have changed between them,
Copilot has actually converged. The skill's "one clean pass" stop
condition is usually right, but on large refactors a second clean
pass with no change-surface between them is a stronger signal.

## Special cases

### Copilot re-raises a finding you already addressed

Reply once pointing at the original thread, then move on:

> Already addressed in `abc1234` (see earlier thread
> https://github.com/<owner>/<repo>/pull/<N>#discussion_r<id>). No
> code change needed.

Do NOT push a new commit to "silence" it. That invites a third round on
the same finding.

### Copilot and a human reviewer disagree

Trust the human. Copilot optimises for patterns; humans see context the
model missed. Reply to Copilot's comment with the human's rationale.

### You forgot to resolve a thread before merging

If the PR merged with open threads, go back and resolve them from the
closed PR's page. The UI still lets you resolve a thread post-merge;
the GraphQL mutation still works. Leaving orphaned open threads on a
merged PR is a minor mess, but it rots — a month from now a reader
can't tell if the thread was unaddressed or just forgotten.
