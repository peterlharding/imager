---
name: cut-release
description: Cut an Imager release - pick the version, bump MARKETING_VERSION, write the changelog and release notes, build, test, commit, tag, and optionally push and publish a GitHub release. Use whenever the user asks to cut, prepare, or ship a release, or asks whether the repo is ready to release.
---

# Cutting an Imager release

`RELEASING.md` at the repo root is the authoritative process. Read it first and follow its
numbered steps. This skill records the operational details that live outside that document.

## Before anything, take stock

Run these and report the actual state rather than assuming:

```sh
git log --oneline -5
git status --short
grep -n MARKETING_VERSION Imager.xcodeproj/project.pbxproj   # expect two matching lines
sed -n '/## \[Unreleased\]/,/^## \[/p' CHANGELOG.md          # what is actually pending
git rev-list --left-right --count origin/main...main         # unpushed commits
```

A release is only "done" when the version bump, changelog entry, release notes file, commit,
and annotated tag all exist and agree.

## Choosing the number

Semantic versioning, per `RELEASING.md`. Most releases are MINOR.

Do not let a round number drive the decision. If the pending changes are one feature plus some
tightening, that is a MINOR bump even if the user floated "1.0.0". Say so once, give the
version the changes actually justify, and let the user overrule you - shipping 1.0.0 as a
statement of completeness is a legitimate product call, just not one semver derives.

## Commit shape

`RELEASING.md` says documentation and process changes get their own `docs:` commit rather than
being folded into the release commit. Honour this even when the release is *about* docs:

- `docs: <summary>` for the README, RELEASING.md, or Xcode Documentation group changes
- `Release <version>` for version bump + CHANGELOG + `release_notes/<version>.md` only
- `feat:` / `fix:` / `test:` for code, committed before the release commit

One `Release <version>` commit per tag, so each tag anchors a distinct point.

## Verifying, not assuming

- **Build and test must both be clean** (step 5). Do not cut on a failing or flaky suite.
- **Confirm the built version**, don't trust the sed:
  ```sh
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    ~/Library/Developer/Xcode/DerivedData/Imager-*/Build/Products/Debug/Imager.app/Contents/Info.plist
  ```
- **After pushing, verify against the live remote**, not the cached remote-tracking ref.
  `git push` has printed `Everything up-to-date` here while refs genuinely needed pushing:
  ```sh
  git ls-remote origin | grep -E "refs/heads/main|refs/tags/v<version>"
  ```
  Compare against `git rev-parse main v<version>^{}`.

## Pushing and publishing

Pushing and creating GitHub releases are outward-facing. Confirm with the user before either,
even mid-flow - approval to commit and tag is not approval to publish.

GitHub releases were adopted starting at **v0.10.0**. Do not backfill v0.3.0-v0.9.2; that was a
deliberate decision. v0.1.0 and v0.2.0 have no tags at all.

**Releases on this repo are immutable. Creating one is a one-shot, irreversible act.**

- Assets cannot be added later. `gh release upload` fails with
  `HTTP 422: Cannot upload assets to an immutable release`.
- Deleting the release does **not** give you another go. The tag name stays reserved, and
  recreating fails with `tag_name was used by an immutable release`, leaving that version with
  no release page and no way to make one. This has already cost v0.13.0 its release page.
- So: if the release is carrying a download, build, notarise, staple and *verify* the artifact
  first (RELEASING.md step 9), then create the release once with the file attached.

```sh
gh release create v<version> --title "Imager <version>" \
  --notes-file release_notes/<version>.md \
  build/Imager-<version>.zip
```

Never delete an immutable release hoping to recreate it. If a release is wrong, the recoverable
paths are cutting the next patch version or leaving it and correcting forward - ask the user which.

Create them oldest-first when publishing several, so "Latest" lands on the newest. `gh` is
installed and authenticated as `peterlharding` over SSH. `gh auth login` is interactive - ask the
user to run it with `! gh auth login` rather than attempting it.

## When an answer does not fit, check before acting on it

PLH's keyboard sometimes drops or mangles characters. If a value, name or version in his reply
contradicts something already established, stop and confirm rather than acting on it — and
especially rather than reshaping the work to accommodate it.

The signal is **contradiction with a known fact**, not mere surprise:

- a number outside a range that was just stated
- a version that does not exist, or is lower than the current one
- a filename or recipe name that does not match anything present
- an instruction that undoes something agreed a moment earlier

Name the specific inconsistency: *"40 is below the 60 minimum — did you mean 140?"*
Do not substitute a different interpretation of your own. On 2026-07-31 the answer "40pt is good"
came back to a question about a 140 pt default, with 60 documented as the minimum one message
earlier. The out-of-range value was the tell; instead of naming it I asked whether he had meant a
radius rather than a diameter, then lowered the minimum so the suspect value would fit. He meant
140.

This is not licence to second-guess every input. Ordinary answers, including terse or surprising
ones, are taken at face value.

## Two standing notes

- PLH's global "never hand-edit CHANGELOG.md" rule does **not** apply to this repo. There is no
  changelog generator; `RELEASING.md` step 3 mandates editing it by hand.
- Release notes are written from the actual diff (`git show <commit>`), not from memory. Check
  feature claims against the source before writing them down.
