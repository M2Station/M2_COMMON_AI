# Copilot Instructions

> This file is the project-level guidance for GitHub Copilot / Copilot Chat, **designed to be reusable across projects**.
> Location: `.github/copilot-instructions.md`
>
> This file records no project-specific information (name, tech stack, directory structure) - these are always
> discovered by the agent per Section 2. It can therefore be copied verbatim into any repo, or synced automatically from a central repo.
> Sections marked "(conditional)" apply only when the project matches that shape.

---

## 1. Communication

- Use **Traditional Chinese** for conversational replies; always use **English** for code, variable names, commit messages, and API naming.
- Keep technical terms in their original English (e.g. firmware, schedule, dependency, build); do not force-translate them.
- Answers should be concise and give the conclusion and runnable code directly; no pleasantries or restating the question.
- State "not sure" explicitly where uncertain; do not guess APIs, parameter names, or file structure.
- When the user must **choose or confirm** anything, render the options as a **real interactive choice list (actual clickable buttons)** using the client's built-in question/choice prompt mechanism — do **not** merely print `[Option]` brackets as text in a normal reply, which renders as plain text and forces the user to type. Always **mark exactly one option as the recommended default** (append `（最建議）` to its label, or set the prompt's "recommended" flag). Free typing stays available only as a fallback. This applies to every decision point, confirmations included.
- **Emit an audible cue whenever you need the user.** Before you pause for input, a choice, or any confirmation — i.e. any point where you hand control back and wait — play a short beep via a quick terminal command so the user notices without watching the screen: PowerShell `[console]::beep(880,200); [console]::beep(1320,300)` (bash/zsh: `printf '\a'`). Best-effort only (depends on OS sound); for a reliable native chime the user can additionally enable VS Code Accessibility Signals — run **Help: List Signal Sounds** or configure `accessibility.signals.*` in settings.

---

## 2. Obtaining Project Context

**Assume no project information.** At the start of each work session, or before performing any cross-file task, discover the project context yourself; do not ask the user to repeat it:

```bash
cat README.md 2>/dev/null | head -60          # project purpose, how to start
cat package.json pyproject.toml Cargo.toml 2>/dev/null   # tech stack, scripts, version location
ls .github/workflows/                          # CI/CD, release method
git log --oneline -15                          # commit conventions, recently active areas
ls -a                                          # config files, project structure
```

Judgment principles:

- **Use the actual files in the repo as the sole basis**; do not rely on assumptions in this file, and do not apply experience from other projects.
- Always derive tech stack, directory structure, naming style, and deployment method from existing code, and follow them.
- When the README or config files lack key information (e.g. start command, deployment target), **ask directly**; do not guess or invent conventions.
- If the project root also has `AGENTS.md`, `CONTRIBUTING.md`, or `docs/`, read and follow them first.
- This file describes **general conventions**; when they conflict with the project's actual conventions, **the project's actual conventions take precedence**.

---

## 3. Technology Choices

Do not assume a tech stack - follow the discovery results from Section 2. The following are general cross-project principles:

- **Follow the project's existing technology**; do not introduce new frameworks, build tools, or abstraction layers out of personal preference.
- Determine the runtime environment (shell, package manager, Node/Python version) from the project config files; when it cannot be determined, ask, do not assume.
- Generated command syntax must match the user's shell (PowerShell / bash / zsh); when unsure, ask first or provide both.

### Dependency Principles

- **Prefer native APIs**; avoid introducing new packages for small features.
- Before adding a dependency, explain the rationale and alternatives, and confirm whether a similar package already exists in the project.
- Do not use unmaintained packages or ones with known security vulnerabilities.
- CDN resources must pin a version; do not use `latest`.
- Always follow the project's existing lock strategy for versions (`^` / `~` / fully pinned); do not change it yourself.

---

## 4. Code Conventions

### General

- Indentation: 4 spaces (consistent across HTML / CSS / JS); do not use tabs.
- Strings: use single quotes `'` in JS; use backticks for template strings.
- Trailing semicolons: **required**.
- Keep one blank line at end of file; use UTF-8 (no BOM), LF line endings.
- Try to keep line length under 120 characters.

### Naming

| Target | Convention | Example |
|---|---|---|
| Variable / function | camelCase | `parseScheduleRow` |
| Class / constructor | PascalCase | `ScheduleEngine` |
| Constant | UPPER_SNAKE_CASE | `MAX_RETRY_COUNT` |
| File | kebab-case | `schedule-engine.js` |
| CSS class | kebab-case, semantic | `.milestone-bar` |
| CSS variable | `--` + kebab-case | `--accent-cyan` |
| Private member | `_` prefix | `_cache` |

### Writing Functions

- A function does one thing only; consider splitting when it exceeds 50 lines.
- Switch to an options object when there are more than 3 parameters.
- Return explicitly; avoid judgment errors caused by implicitly returning `undefined`.
- Keep side effects (DOM manipulation, file I/O, DB writes) centralized; do not scatter them through computation logic.

### Comments

- Comments explain **why** something is done, not restate what the code does.
- Add JSDoc to public functions (types + purpose + boundary conditions).
- Mark temporary code with `// TODO:` or `// FIXME:` and add the reason.
- **Do not** produce large amounts of meaningless decorative comments or separator lines.

---

## 5. Error Handling

- Always validate external input (files, APIs, user input) before use.
- Do not use empty `catch {}`; at least log it or convert it to an explicit error.
- Error messages must include enough context to locate the problem (file name, field, index value).
- Use fail-fast for unexpected states; do not silently fall back.
- User-visible error messages in Traditional Chinese; logs in English.

---

## 6. Security

- **Strictly forbidden** to write accounts, passwords, tokens, API keys, internal IPs, or customer confidential data into code.
- Put sensitive config in `.env` or config files, and confirm they are added to `.gitignore`.
- Use obviously fake values in example code: `YOUR_API_KEY`, `example.com`.
- Always use parameterized queries (prepared statements) for SQL; never concatenate strings.
- Avoid `innerHTML` when outputting user data on the frontend, prefer `textContent`; escape when necessary.
- When customer names, project codenames, part numbers, cost, or quote information are involved, do not write them into any repo (including commit messages and PR descriptions).

---

## 7. Git Conventions

### Commit Message

Use Conventional Commits:

```text
<type>(<scope>): <subject>

<body optional, describing the motivation and scope of impact>
```

**type**: `feat` / `fix` / `refactor` / `perf` / `docs` / `style` / `test` / `chore` / `build`

- Subject uses English, starts with a base-form verb, no more than 72 characters, no trailing period.
- One commit contains only one logical change.
- Example: `feat(scheduler): add reverse planning for PCB milestones`

### Branches

- `main`: releasable state; do not push directly.
- `feature/<description>`, `fix/<description>`, `chore/<description>`.
- PRs need a self-check: it runs, no console error, no leftover debug code.

---

## 8. Copilot Behavior

**Must do:**

- Use a **minimal diff** when modifying existing files; do not casually reorder or reformat unrelated blocks.
- Reference the project's existing style and naming before editing; prioritize consistency over personal preference.
- Produced code must be directly runnable; do not leave placeholders like `...` or `// other logic`.
- For multi-file changes, list the plan before starting.
- Before large refactors, deleting files, or changing data structures, **ask for confirmation first** — via the **interactive choice prompt with real buttons** defined in Section 1 (one option marked `（最建議）`), e.g. **[Proceed]（最建議） / [Cancel]**, not as text the user must type.

**Do not:**

- Do not fabricate nonexistent functions, packages, config items, or file paths.
- Do not add frameworks, build tools, or abstraction layers when not asked.
- Do not change existing UI behavior or visual style for the sake of "improvement".
- Do not output lengthy preambles, summaries, or re-paste the entire unmodified file.
- Do not remove existing comments, TODOs, or seemingly useless but unconfirmed code.

---

## 9. Workflow Routing (Prompt Files)

When the user's message matches the semantics below, **read the corresponding prompt file before acting**, and follow that file's steps exactly; do not improvise the flow.

| Trigger semantics | Corresponding file | Description |
|---|---|---|
| `review` / `code review` / self review / "check this" / "take a look at these changes" | `.github/prompts/m2_review.prompt.md` | Self code review, **do not modify code** |
| `pr` / `PR` / "open PR" / "submit for review" / `open pull request` | `.github/prompts/m2_pr.prompt.md` | Open PR -> monitor CI every 3 seconds -> remind the user to confirm the merge |
| `next` / `cleanup` / "wrap up" / "clean up branches" / "back to main" / "ready for next" / "收尾" / "準備下一輪" | `.github/prompts/m2_next.prompt.md` | Post-merge cleanup -> delete merged branch, sync main, verify clean tree, ready for next |
| `release` / "ship a version" / "publish a new version" / "cut a release" / `bump version` | `.github/prompts/m2_release.prompt.md` | Version bump -> PR -> merge -> tag -> CI publish |
| `release ci` / `installer` / "portable + setup" / "silent install" / "packaging spec" / "打包規格" / "發版 CI" / "自動更新裝不起來" | `.github/prompts/m2_release.prompt.md` (**Appendix A**) | Release CI spec: Portable + Setup per arch, silent-install contract, asset naming |
| `evolve` / "iterate until done" / "keep improving" / "autonomous optimization" / "一直改到好" / "自主迭代" / "持續優化" / `resume` a long run | `.github/prompts/m2_evolve.prompt.md` | Long-running self-iterating optimization: interview -> charter -> baseline -> iterate (sense/plan/act/verify/judge) -> smoke test -> commit or revert, on a 12h budget with a resumable ledger |

### Routing Rules

- Standard flow order: `/m2_review` -> fix -> `/m2_pr` -> user confirms merge -> `/m2_next` (cleanup) -> `/m2_release` when cutting a version.
- If the user only says "release" without specifying a version -> compute the next version per the prompt file rules, report it, then execute.
- When no prompt file matches, **do not invent a release or PR flow** - ask first.
- When a prompt file's rules conflict with this file, **the prompt file takes precedence** (it is the dedicated spec for that task).
- **Appendix A of `m2_release.prompt.md` is a specification, not a flow**: read it only when building/changing build & release CI or installer scripts (or porting the spec to another repo). A routine version release uses sections 1-5 only and must NOT touch the workflow.
- `/m2_evolve` is **orthogonal to the standard flow**: it produces commits on a dedicated `evolve/*` branch and deliberately never opens or merges a PR itself. When a round ends, hand off to `/m2_pr` as usual.
- The four flow prompts (`m2_review` / `m2_pr` / `m2_next` / `m2_release`) each have a "stop and wait for user confirmation" node; do not skip it for the sake of a smooth flow. **The only exception is auto mode below, and only when the user typed `auto` explicitly.**

### Auto Mode (`<command> auto`)

Appending `auto` switches `/m2_pr`, `/m2_next`, and `/m2_release` to **fully autonomous**: the agent
resolves every confirmation node itself, runs the flow to completion, and delivers one consolidated
workflow + result report at the end instead of stopping mid-flow.

- `auto` is a trailing modifier and composes with existing arguments:
  `/m2_pr auto`, `/m2_pr draft auto`, `/m2_next 42 auto`, `/m2_release 0.4.1 auto`.
- **Only these three support `auto`.** `/m2_review` changes no state (nothing to confirm) and
  `/m2_evolve` already has `checkpoint silent`; do not invent an `auto` mode for them.
- Without a literal `auto`, the interactive confirmation nodes remain mandatory.
  **Never infer auto mode** from phrases like "just do it" or "don't ask me".

**Decision rule.** At every node that would have been a button prompt:

1. Choose the option supported by repo history or existing convention (tag format, PR format, merge strategy, branch naming).
2. If the repo offers no defensible basis **and** the action is irreversible -> **abort and report**.
   "The agent decides" never means "guess and hope".

**ABORT conditions - `auto` does NOT waive any of these.** On any of them, stop immediately, change
nothing further, and report the state plus what the user must decide:

| Condition | Why |
|---|---|
| CI red, timed out, or cancelled | Never merge on red. Never rerun-until-green, `--admin`, `continue-on-error`, `--no-verify`, or edit a workflow to make it pass. |
| Secrets, tokens, internal IPs, or customer data in the diff | Section 6. |
| Uncommitted tracked changes at a step that switches or deletes branches | May be work in progress. |
| Local branch is behind `origin`, or `git pull` is not fast-forward | Working on a stale base silently reverts other people's merged work. Never rebase or force to "fix" it. |
| PR identity cannot be verified authoritatively | See below. |
| Tag already exists, or the computed version number is already in `CHANGELOG.md` | Never `-f`, never delete an existing tag, never reuse a version. |
| Merge conflict, or `mergeStateStatus` is `DIRTY` / `BLOCKED` / `BEHIND` | Needs a human. |
| A required review is missing, or branch protection would have to be bypassed | Never bypass. |

**Never, in any mode:** force push, `git reset --hard`, `git clean -fd`, delete untracked files,
`git branch -D`, push directly to `main`, or publish artifacts from a local machine.

**Freshness check is mandatory before auto mode does anything.** Run `git fetch origin` and confirm
`git rev-list --left-right --count origin/main...HEAD` reports `0` on the left. A stale local `main`
is the single most destructive failure mode: every edit is then made against outdated files, and the
resulting PR reverts whatever was merged in between.

**Identity verification is mandatory before any merge or branch deletion in auto mode.**
`gh pr create` output and `gh pr list` are not trustworthy on their own - a printed URL can point at
an unrelated PR, and a listed number can 404. Confirm via the REST API that the head branch and title
are the ones you just produced:

```bash
gh api "repos/{owner}/{repo}/pulls?head={owner}:<branch>&state=open" --jq '.[].number'
gh api repos/{owner}/{repo}/pulls/<n> --jq '{head:.head.ref, base:.base.ref, title, state, merged}'
```

**Final report (required).** Auto mode is quiet while running but must end with a single report
covering: (a) every step actually executed, in order; (b) each decision the agent made on the user's
behalf and the basis for it; (c) final state - PR link, merge SHA, tag, branches deleted, CI run
links; (d) anything still left for the user. Never report a step as done if it did not run.

## 10. Single-File HTML Tool Conventions (conditional)

> **Applies only when the project's main output is a single-file `.html` tool that opens directly in a browser.**
> When the project does not match this shape, ignore this whole section; do not apply it to general web projects.

- All HTML / CSS / JS is concentrated in a single `.html`, openable directly in a browser, no server required.
- External resources allowed only: Google Fonts, and CDN libraries served from a CDN (pinned versions).
- Section order inside the file: `<style>` -> `<body>` structure -> `<script>`, each section marked with a block comment.
- State is centrally managed in a single `state` object; avoid scattered global variables.
- Use `localStorage` for data persistence; prefix keys with the project name to avoid collisions.
- When export is needed (JSON / Excel / PPTX), make the feature a standalone function; do not mix it with render logic.

---

## 11. Visual Design Conventions (conditional)

> **Applies as the default style only when the project has no existing design system and the UI must be built from scratch.**
> When the project already has design tokens, CSS variables, or a component library, **always follow the existing system** and ignore this section.

- Dark background, high contrast, high information density; avoid large empty areas and rounded cartoonish styles.
- Fonts: `Orbitron` for headings, `DM Mono` for data and code, `Noto Sans TC` as the Chinese fallback.
- Palette: neon accents with cyan (`#00e5ff`) as primary and magenta (`#ff2fd0`) as secondary.
- Always define colors as CSS variables under `:root`; do not hardcode color codes in components.
- Restrained motion: transitions of 150-250ms; no bounce or exaggerated entrance animations.
- Tables, Gantt charts, and dashboards must support large amounts of data; prioritize readability and scroll performance.

---

## 12. Testing and Validation

<!-- TODO: projects without a test framework can simplify this to a manual checklist -->

- New logic needs a minimal verifiable method (unit test or runnable example).
- Boundary conditions must be tested: null, empty array, single element, maximum value, invalid input.
- Pre-delivery checklist:
  - [ ] Starts / opens normally, no console error
  - [ ] Main flow walked through manually once
  - [ ] No leftover `console.log` or test data
  - [ ] No hardcoded secrets
  - [ ] README / comments updated accordingly
