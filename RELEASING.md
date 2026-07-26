# Releasing Imager

This document describes the release process for Imager.
Follow these steps for every release so that the version number, changelog, release notes, and git tag stay in sync.

## Versioning

Imager uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html): `MAJOR.MINOR.PATCH`.

- MAJOR: incompatible or sweeping changes.
- MINOR: new, backward-compatible features (most releases so far).
- PATCH: backward-compatible bug fixes only.

The user-facing version is the `MARKETING_VERSION` build setting.
The `CURRENT_PROJECT_VERSION` build setting is the build number and can be bumped independently.

## Where versions live

- `MARKETING_VERSION` in `Imager.xcodeproj/project.pbxproj` (set in both the Debug and Release configurations - two occurrences).
- `CHANGELOG.md` at the repo root, following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
- `release_notes/<version>.md`, one user-facing file per release.
- The git tag `v<version>` (annotated).

## Release steps

1. **Pick the version number** based on the nature of the changes (see Versioning above).

2. **Bump `MARKETING_VERSION`** to the new version in `Imager.xcodeproj/project.pbxproj`.
   Update both occurrences (Debug and Release). For example:

   ```sh
   sed -i '' 's/MARKETING_VERSION = 0.3.0;/MARKETING_VERSION = 0.4.0;/g' Imager.xcodeproj/project.pbxproj
   grep -n MARKETING_VERSION Imager.xcodeproj/project.pbxproj   # expect two matching lines
   ```

3. **Cut the changelog.** In `CHANGELOG.md`:
   - Move the items under `## [Unreleased]` into a new `## [<version>] - YYYY-MM-DD` section (today's date).
   - Leave a fresh, empty `## [Unreleased]` at the top.
   - Add a `See [release_notes/<version>.md](release_notes/<version>.md) for details.` line under the new heading.
   - Update the link references at the bottom of the file: point `[Unreleased]` at `compare/v<version>...HEAD` and add a `[<version>]` tag link.

4. **Write the release notes** at `release_notes/<version>.md`.
   Use the existing files as a template: a short intro, Highlights, any Fixed section, and Under the hood.

5. **Build clean** and confirm there are no warnings:

   ```sh
   xcodebuild -project Imager.xcodeproj -scheme Imager -configuration Debug -destination 'platform=macOS' build
   ```

6. **Commit** the version bump, changelog, and release notes together:

   ```sh
   git add -A
   git commit -m "Release <version>"
   ```

7. **Tag** the release with an annotated tag:

   ```sh
   git tag -a v<version> -m "Imager <version>"
   ```

8. **Push** the commit and the tag:

   ```sh
   git push origin main
   git push origin v<version>
   ```

9. **(Optional) Publish a GitHub release** from the tag, using the matching `release_notes/<version>.md` as the body:

   ```sh
   gh release create v<version> --title "Imager <version>" --notes-file release_notes/<version>.md
   ```

## Notes

- The repo-level docs (`CHANGELOG.md`, `RELEASING.md`, `README.md`, `LICENSE`, `release_notes/`) live at the repo root, outside the Xcode-synchronized `Imager/` source group. They are visible in Xcode under the `Documentation` group but are not compiled into the app.
- Tags are annotated (`git tag -a`) so they carry a message and tagger, and can be verified and listed with release metadata.
- Keep one commit per release (`Release <version>`) going forward so each tag anchors to a distinct, accurate point in history.
