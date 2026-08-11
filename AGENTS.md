# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Use `swift test` for the focused core suite and `./scripts/build-app.sh` for the release bundle/signature check; see `README.md` for the install workflow.
- Keep quota policy and schema handling in `Sources/QuotaBarCore`; synthetic schema fixtures belong in `Tests/QuotaBarCoreTests/Fixtures` and must never contain live quota, identity, credential, token, or machine-path data.
- The first-release product and privacy contract is documented in `README.md`; in particular, preserve truthful unknown/stale states and do not add notifications.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
