# Repository Instructions

This repository holds various Raspberry Pi projects, settings, and scripts.

## Structure

- One top-level folder per project or collection of scripts.
- Each project folder has its own `README.md` describing what it is, what hardware it needs, and how to run it.
- Project-specific instructions belong in that project's folder, not in this file.

Keep `README.md` short and practical: what to do, in order, and the commands to do it
with. A reader should not have to wade through reasoning to set something up.

Background, justifications for design choices, findings, and rules for changing the
project go in an `AGENTS.md` inside that project folder, linked from its `README.md`.
Nobody has to read it to use the project.

A project may have a `tools/` folder for scripts that are useful around it but are not
part of running it, such as checkers and diagnostics.

The repository is mostly empty for now and grows one folder at a time.

## Working Guidelines

- Keep each project self-contained in its own folder. Do not add shared code between projects unless the user asks for it.
- When you create a new project folder, create its `README.md` at the same time.
- When you change how a project is installed, configured, or run, update that project's `README.md` in the same change.
- Scripts are meant to run on a Raspberry Pi (Linux), even though the repository is edited on Windows. Use Linux paths and shell syntax inside scripts.
- Keep repository-level instructions in this file. Other assistant-specific files should reference this file instead of duplicating these rules.

## Code Style

- Prefer plain English over jargon, in code and in explanations.
- Prefer names like `save_*`, `load_*`, `update_*`, `build_*`, `fetch_*`, and `find_*`.
- Write comments and docs in simple English. Explain intent, not obvious mechanics.
- Avoid one-line helpers, especially when used only once. Keep the logic inline with a short comment instead.
