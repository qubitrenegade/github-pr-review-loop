# Triage patterns — apply, dismiss, clarify

Templates and examples for each of the three triage categories, plus the
evidence checklist for dismissals.

## Contents

- Apply — fix + cite commit SHA
- Dismiss — reply with empirical evidence
- Clarify — ask before guessing
- Evidence checklist (what to run for each claim type)
- Batching multiple findings into one push

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
> process exit. No teardown risk bounded to 5s.

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
- Write triage decisions next to each (apply / dismiss / clarify).
- Apply all the "apply" fixes, group by theme if sensible.
- Commit once (or with semantic boundaries: fix, docs, style).
- Push.
- Post all replies in one pass.
- Re-request review once.

Pushing a commit for each finding individually multiplies the Copilot
rounds and sends the same diff through N reviews. Wasteful.

## Special cases

### Copilot re-raises a finding you already addressed

Reply once pointing at the original thread, then move on:

> Already addressed in `abc1234` (see earlier thread
> https://github.com/<owner>/<repo>/pull/<N>#discussion_r<id>). No
> code change needed.

Do NOT push a new commit to "silence" it. That invites a third round on
the same finding.

### Copilot's finding is right in principle, but the fix is out of scope

Acknowledge the finding, file a follow-up issue, and link it:

> Valid concern. Filed as #<N> for a dedicated cycle; out of scope for
> this PR which is focused on <X>. The proposed change would
> <consequence outside this PR's scope>.

This keeps the current PR moving without losing the finding.

### Copilot and a human reviewer disagree

Trust the human. Copilot optimises for patterns; humans see context the
model missed. Reply to Copilot's comment with the human's rationale.
