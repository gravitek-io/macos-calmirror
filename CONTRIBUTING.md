# Contributing to CalMirror

Thanks for taking the time to contribute. CalMirror is a small project and
every kind of help matters: bug reports, testing with a calendar provider we
have not tried, documentation fixes, or code.

## Ways to contribute

- **Report a bug** using the bug report template. Include your macOS version,
  the account types involved (Google, Microsoft 365, iCloud, Exchange, CalDAV)
  and, when relevant, the output of `calmirror status --json` and
  `calmirror logs --limit 20`.
- **Test with your own setup.** CalMirror works with any account that Apple
  Calendar can sync. Reports that "it works with provider X" (or does not) are
  valuable in themselves.
- **Suggest a feature** using the feature request template. Explain the
  problem you are trying to solve before proposing a solution.
- **Improve the documentation.** If something in the README was unclear to
  you, it will be unclear to others.
- **Submit code** following the workflow below.

## Development setup

| Requirement | Version |
|-------------|---------|
| macOS | 26 or later |
| Xcode | 26 or later (provides the Swift 6.2+ toolchain) |
| Calendar accounts | at least two calendars configured in Apple Calendar |

```bash
git clone https://github.com/gravitek-io/macos-calmirror.git
cd macos-calmirror

swift build              # build every target
swift test               # run the unit tests
swift run calmirror calendars   # exercise the CLI from source
open Package.swift       # open the package in Xcode
```

To try the GUI app and the launchd agent end to end, install a local build
with `./scripts/install.sh`. See the README for what it installs and how to
remove it.

## Workflow

1. Fork the repository and create a branch from `main`
   (for example `feat/short-description` or `fix/short-description`).
2. Make your change. Keep pull requests focused on a single topic: a small,
   reviewable PR is merged faster than a large one.
3. Run `swift test` and make sure it is green.
4. Open a pull request against `main` and fill in the template. Continuous
   integration builds and tests every PR; it must pass before merge.
5. A maintainer reviews the PR. Pull requests are squash-merged, so the PR
   title becomes the commit message on `main` and must follow the commit
   conventions below.

Direct pushes to `main` are not allowed, including for maintainers.

## Commit messages

Commits and PR titles follow [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add a per-rule sync interval
fix: skip declined source events
docs: clarify Calendar app requirement
chore(release): bump version to 1.2.0
```

Common types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `ci`.
Versions follow [Semantic Versioning](https://semver.org/).

## Code guidelines

- **Language.** Source code, comments, documentation and commit messages are
  written in English.
- **Document intent.** Every type and non-trivial function carries a doc
  comment explaining its purpose and, when the logic is not obvious, why it
  is written that way.
- **Respect the module boundaries.**
  - `CalmMirrorCore` holds the models, the sync engine, storage and calendar
    access. It has no UI and no CLI concerns.
  - `CalmMirrorApp` is the SwiftUI front end. It only talks to the core.
  - `calmirror` is the command line front end. It only talks to the core.
- **Keep it simple.** Prefer the straightforward solution unless it hurts
  security, maintainability or the user experience. Do not add folders,
  abstractions or dependencies for hypothetical future needs.
- **Tests.** Behaviour in `CalmMirrorCore` is covered by unit tests in
  `Tests/CalmMirrorCoreTests`. Add or update tests with your change. The goal
  is to catch regressions early, not to reach a coverage number.
- **Follow the existing style** of the file you are editing.

## Safety invariants

CalMirror writes into people's calendars, so a few rules are not negotiable.
A pull request that breaks one of them will not be merged:

1. **The source calendar is never modified.** CalMirror only reads from it.
2. **Only CalMirror's own blockers are touched in the target calendar.**
   Every managed blocker carries the "Managed by CalMirror" tag in its notes,
   and events without it are never updated or deleted.
3. **Only the data the user opted into leaves the source event.** In mirror
   mode that is the title; with a fixed placeholder, nothing. Location,
   notes, attendees, URLs, alarms and recurrence are never copied.
4. **No network access.** CalMirror talks to Apple Calendar through EventKit
   and nothing else. No telemetry, no remote calls, no data leaving the Mac.

## Releases

Releases are cut by maintainers; the procedure is documented in
[docs/RELEASING.md](docs/RELEASING.md).

## Code of conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By
participating you agree to uphold it.
