> **Status (2026-10-12): historical.** The current design is the **redesign
> v2** (direction A+, "Native Refined"): spec in
> [`design/redesign-v2/spec.md`](redesign-v2/spec.md), per-phase plans in
> [`design/redesign-v2/plans/`](redesign-v2/plans/), and the Claude Design
> canvas "gitForge — Redesign". The app implements it fully since phase F9;
> the v1 design system is gone. This bundle below is the original handoff the
> first UI was built from — keep it only as historical context. Its paths
> were written for the original bundle layout (the files live in
> `design/design/`, e.g. `design/design/GitForge.html`).

# CODING AGENTS: READ THIS FIRST

This is a **handoff bundle** from Claude Design (claude.ai/design).

A user mocked up designs in HTML/CSS/JS using an AI design tool, then exported this bundle so a coding agent can implement the designs for real.

## What you should do — IMPORTANT

**Read `gitforge/project/GitForge.html` in full.** The user had this file open when they triggered the handoff, so it's almost certainly the primary design they want built. Read it top to bottom — don't skim. Then **follow its imports**: open every file it pulls in (shared components, CSS, scripts) so you understand how the pieces fit together before you start implementing.

**If anything is ambiguous, ask the user to confirm before you start implementing.** It's much cheaper to clarify scope up front than to build the wrong thing.

## About the design files

The design medium is **HTML/CSS/JS** — these are prototypes, not production code. Your job is to **recreate them pixel-perfectly** in whatever technology makes sense for the target codebase (React, Vue, native, whatever fits). Match the visual output; don't copy the prototype's internal structure unless it happens to fit.

**Don't render these files in a browser or take screenshots unless the user asks you to.** Everything you need — dimensions, colors, layout rules — is spelled out in the source. Read the HTML and CSS directly; a screenshot won't tell you anything they don't.

## Bundle contents

- `gitforge/README.md` — this file
- `gitforge/project/` — the `GitForge` project files (HTML prototypes, assets, components)
