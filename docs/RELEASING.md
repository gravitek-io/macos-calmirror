# Releasing CalMirror

This document describes how to cut a new CalMirror release. The packaging is
automated by [`scripts/package-release.sh`](../scripts/package-release.sh); the
human steps are the version bump, the changelog/notes, and publishing.

## Overview

```mermaid
flowchart TD
    A[Bump version in source] --> B[Commit + annotated tag vX.Y.Z]
    B --> C[scripts/package-release.sh]
    C --> D[dist/calmirror-X.Y.Z-macos-arm64.tar.gz]
    D --> E[gh release create vX.Y.Z]
```

A release ships a single asset, a `.tar.gz` containing a self-installing
directory:

```
calmirror-X.Y.Z/
  CalMirror.app   # ad-hoc code-signed GUI bundle
  calmirror       # CLI binary (arm64)
  install.sh      # prebuilt installer (from scripts/release-install.sh)
```

**Target platform:** macOS 26+, Apple Silicon (arm64). Build on an
Apple Silicon Mac.

## 1. Bump the version

Update **every** version reference so the app, CLI and library agree. Missing
one produces an inconsistent release.

| File | What to change |
|------|----------------|
| `Sources/CalmMirrorApp/Info.plist` | `CFBundleShortVersionString` and `CFBundleVersion` |
| `Sources/calmirror/CLI.swift` | `print("calmirror X.Y.Z")` in the `Version` command |
| `Sources/CalmMirrorCore/CalmMirrorCore.swift` | `public static let version = "X.Y.Z"` |
| `Tests/CalmMirrorCoreTests/CalmMirrorCoreTests.swift` | `testCoreLibraryVersion` asserts the version — keep it in sync |

After bumping, `swift test` must stay green (`testCoreLibraryVersion` guards the
library version).

Follow [SemVer](https://semver.org/): bug fixes → patch, backward-compatible
features → minor, breaking changes → major.

> The packaging script guards against a mismatched **CLI** version, but it
> cannot check the others — update them all.

## 2. Merge the bump and tag `main`

`main` only changes through pull requests, so the version bump lands like any
other change:

```bash
git checkout -b chore/release-X.Y.Z
git commit -am "chore(release): bump version to X.Y.Z"
git push -u origin chore/release-X.Y.Z
gh pr create --title "chore(release): bump version to X.Y.Z" --fill
```

Once the PR is merged, tag the resulting commit on `main`:

```bash
git checkout main && git pull
git tag -a vX.Y.Z -m "vX.Y.Z — <one-line summary>"
git push origin vX.Y.Z
```

The tag must point at the commit you intend to ship; `package-release.sh`
infers the version from the tag on `HEAD`.

## 3. Build the archive

```bash
./scripts/package-release.sh            # version inferred from the HEAD tag
# or
./scripts/package-release.sh X.Y.Z      # explicit version
```

The archive lands in `dist/` (git-ignored). The script ad-hoc code-signs the
app bundle and verifies the CLI reports the expected version.

## 4. Publish the GitHub release

Write release notes (mirror the structure of previous releases: a one-line
summary, a "What's new" list, an Installation block, and a compare link), then:

```bash
gh release create vX.Y.Z \
  -R gravitek-io/macos-calmirror \
  --title "CalMirror X.Y.Z" \
  --notes-file notes.md \
  dist/calmirror-X.Y.Z-macos-arm64.tar.gz
```

The compare link convention is
`https://github.com/gravitek-io/macos-calmirror/compare/v<prev>...vX.Y.Z`.

## 5. Verify

```bash
gh release view vX.Y.Z -R gravitek-io/macos-calmirror
```

Confirm the asset is attached and, ideally, download it on a clean machine and
run `./install.sh` to smoke-test the install flow.
