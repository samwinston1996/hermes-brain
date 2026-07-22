---
name: findings-first-workflow
description: "Investigate first, present findings, get explicit approval — never patch or restart before the user says go."
trigger: Any time you are investigating a bug, issue, or unexpected behaviour with the intent to fix it.
lang: en
related_skills:
  - systematic-debugging
  - session-startup-ritual
  - two-phase-workflow
---

# Findings-First Workflow

## Core Rule

**NEVER write a patch, edit a file, or restart a container before presenting your findings to the user and getting explicit go-ahead.**

This rule overrides urgency. The smallest fix needs the most careful gate.

## Protocol

### Phase A — Investigate (systematic)

Follow the `systematic-debugging` skill's Phase 1 (Root Cause Investigation) through Phase 3 (Hypothesis). Build a tight feedback loop. Trace the data flow. Form ranked hypotheses.

### Phase B — Present Findings & Propose

Deliver a root-cause brief:

| What to cover | Example |
|---------------|---------|
| **Symptom** | What the user reported seeing |
| **Root cause** | Why it happens (not the symptom itself) |
| **Evidence** | Log lines, code paths, data flow traces — compact |
| **Proposed fix** | What you want to change, and **why this works** |
| **Alternatives considered** | Other approaches and why they're inferior (if relevant) |

Use a table or short bullet list — never a narrative. The user should be able to scan the gist in 5 seconds.

**Explain the WHY.** If the user challenges your approach ("why not just do X?"), answer directly. Don't defend a wrong theory — update and re-present.

**Problem & Solution Statement format (preferred for multi-bug reviews):** When the user asks for a consolidated summary of several issues, organize them as a numbered table with each bug getting:

| # | Bug | Root Cause | Fix | Priority |
|---|-----|-----------|-----|----------|
| 1 | One-line symptom | One-line root cause | One-line fix approach | High/Medium/Low |

This format is the user's preferred deliverable for multi-issue investigations — it's scannable in 5 seconds and directly actionable. Always append it after the individual root-cause briefs when presenting 3+ issues in one turn.

### Phase C — Wait for Explicit Go-Ahead

After presenting, stop. Do not code, patch, restart, or git commit in the same turn. Wait for the user to say **"Execute Jarvis"** (the standard two-phase gate) or an explicit "go ahead."

### Phase D — Implement

Only now apply the fix — triggered by **"Execute Jarvis"** per the two-phase-workflow skill. One change at a time. Patch the **source files**, not the running instance.

### Phase E — Build (if Docker)

Rebuild the artifact from source. For Docker projects:
- `docker compose build <service>` — builds image from source files
- Do NOT edit files inside running containers as a substitute. Container edits are ephemeral — lost on restart and not captured in source control.

### Phase F — Test

Verify the fix works end-to-end:
- Service healthy: `docker compose ps` or equivalent
- Log evidence: check for the expected behaviour change (e.g. specific log lines proving the fix is active)
- No regressions: confirm unrelated functionality still works
- Share specific evidence with the user so they can review

### Phase G — Push

Commit and push after every verified fix:
- Descriptive commit message explaining root cause and what changed
- Push immediately so the user can review the diff on GitHub
- Do not batch multiple fixes into one commit without asking first

### Phase H — Sequential Execution Reporting

When executing a multi-step plan that was approved by the user, report each step individually:

- **On success:** Report "Step X complete" with a brief one-line confirmation. Do not batch multiple steps into one status update.
- **On failure:** Stop immediately. Present the new blocker, propose an alternative approach, and wait for **"Execute Jarvis"** before continuing. Do not attempt silent recovery or fallback — the user must see the failure and sign off on the new path.
- **Never skip the report:** Even if a step seems trivial, report it. The user is tracking progress against the agreed plan, not reading your internal state.
- **Re-plan when blocked:** If the approved plan hits an unexpected blocker, the new plan needs its own approval cycle (Phase B → Phase C with **"Execute Jarvis"**) before execution resumes. The original plan's approval does not carry forward past a failure.

This pattern was explicitly requested by the user as a correction — encode it in every multi-step execution, not just debugging tasks.

## What This Skill Replaces

This skill is the user-specific companion to the bundled `systematic-debugging` skill. The bundled skill covers the technical investigation loop but is missing the **human approval gate** between hypothesis and implementation. This skill adds that gate.

## Pitfalls

| Rationalization | Reality |
|----------------|---------|
| "The fix is obvious, they'll agree" | Obvious fixes are the ones most often wrong. Present it. |
| "I'll explain as I patch" | Explanation + patch in the same turn skips the approval gate. Two turns. |
| "They said okay to similar before" | Prior approval for similar action is not blanket approval. Get it fresh. |
| "It's just a one-line change" | A one-line change can have the biggest downstream impact. |
| "I already showed the evidence, time to code" | Showing evidence is Phase B. You haven't finished until you *waited for a reply*. |
| "They'll see the fix in the diff and can reject it" | Undo is waste. Present before doing, not after. |
| "I'll also tidy up this config file while I'm at it" | **Scope creep.** Only change what was explicitly agreed. Extra files (Dockerfiles, compose, unrelated config) pushed without discussion erode trust. If something else needs fixing, flag it in Phase B — don't bundle it silently. |
| "This line looks unused, I'll remove it" | **Code removal requires explicit approval.** Before removing any existing line or config, check what else it serves. A line that looks unused may be serving a purpose you don't see — network connectivity, fallback paths, environment setup, or a related service. If you find removed code that also supported other functionality, flag it, explain the situation, and get approval before proceeding. Never assume a line is unused without verifying. |

## What Makes This Hard

- When you've traced the root cause and are certain, **coding feels productive** and waiting feels wasteful. The wait is the point — it lets the user override a bad assumption you didn't know you had.
- When the user has high trust, the temptation is to skip. High trust is earned by following the process, not by skipping it.