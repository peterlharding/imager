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

   Also update `FEATURES.md`: move anything this release ships from ToDo to Done, and stamp each
   with `— v<version>`, replacing the `unreleased` marker used while it was waiting.

4. **Write the release notes** at `release_notes/<version>.md`.
   Use the existing files as a template: a short intro, Highlights, any Fixed section, and Under the hood.

5. **Build clean and run the tests.** Confirm there are no warnings and no failures:

   ```sh
   xcodebuild -project Imager.xcodeproj -scheme Imager -configuration Debug -destination 'platform=macOS' build
   xcodebuild test -project Imager.xcodeproj -scheme Imager -destination 'platform=macOS'
   ```

   Do not cut a release on a failing or flaky suite.
   Fix the test or the code first, even when the failure looks unrelated to what the release contains.

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

9. **(Optional) Build and notarise the distributable app**, if this release is going to carry a
   download. Do this *before* creating the GitHub release: see the warning under step 10.

   This needs a Developer ID Application certificate in the login keychain, and notarisation
   credentials stored once as a keychain profile:

   ```sh
   xcrun notarytool store-credentials "imager-notary" --apple-id <apple-id> --team-id T5RDMAD9Q4
   ```

   Then:

   ```sh
   # Build a Release archive.
   xcodebuild archive -project Imager.xcodeproj -scheme Imager -configuration Release \
     -destination 'platform=macOS' -archivePath build/Imager.xcarchive

   # Export it. This step is what re-signs with Developer ID; see ExportOptions.plist.
   xcodebuild -exportArchive -archivePath build/Imager.xcarchive \
     -exportOptionsPlist ExportOptions.plist -exportPath build/export

   # Zip with ditto rather than zip, so symlinks and signing metadata survive.
   ditto -c -k --sequesterRsrc --keepParent build/export/Imager.app build/Imager-<version>.zip

   # Notarise, and wait for the verdict.
   xcrun notarytool submit build/Imager-<version>.zip --keychain-profile "imager-notary" --wait

   # Staple the ticket, then re-zip. The ticket attaches to the .app, so the zip
   # made above does not contain it.
   xcrun stapler staple build/export/Imager.app
   rm build/Imager-<version>.zip
   ditto -c -k --sequesterRsrc --keepParent build/export/Imager.app build/Imager-<version>.zip
   ```

   **Verify before going further.** Extract the zip somewhere and confirm what a downloader
   will see:

   ```sh
   xcrun stapler validate <extracted>/Imager.app
   spctl --assess --type execute --verbose=2 <extracted>/Imager.app
   ```

   Expect `accepted` and `source=Notarized Developer ID`.
   Also confirm with `codesign -dv --verbose=4` that the authority reads
   `Developer ID Application`, not `Apple Development`.
   A development-signed app will not launch on anyone else's Mac, and the archive step signs with
   the development certificate until export replaces it.

10. **(Optional) Publish a GitHub release** from the tag, using the matching
    `release_notes/<version>.md` as the body, and attaching the artifact from step 9 in the
    same command:

    ```sh
    gh release create v<version> --title "Imager <version>" \
      --notes-file release_notes/<version>.md \
      build/Imager-<version>.zip
    ```

    Omit the trailing file for a source-only release.

    > **Releases on this repo are immutable, so creation is a one-shot.**
    > Assets cannot be added afterwards: `gh release upload` against an existing release fails
    > with `HTTP 422: Cannot upload assets to an immutable release`.
    > Worse, deleting the release does not undo anything, because the tag name stays reserved -
    > recreating it fails with `tag_name was used by an immutable release`, leaving the version
    > with no release page and no way to make one.
    > Build and verify the artifact first, then create the release once, with everything attached.

    GitHub marks whichever release was *created* most recently as "Latest", regardless of version
    order, so backfilling an older version steals the badge.
    Put it back with `gh release edit v<version> --latest`.

## Commit conventions

Use a short prefix on commit messages so history is easy to scan.

- `Release <version>` for the single commit that cuts a release (step 6 above).
- `feat: <summary>` for a new feature, `fix: <summary>` for a bug fix.
- `docs: <summary>` for documentation and process changes that are not part of a release.
- `test: <summary>` for test-only changes.
- `build: <summary>` for build, signing, and packaging configuration.

Documentation or process changes (this file, README, the Xcode Documentation group) are committed
on their own with a `docs:` message rather than being folded into a release commit. For example:

```sh
git add RELEASING.md Imager.xcodeproj/project.pbxproj
git commit -m "docs: add release process"
```

## Notes

- The repo-level docs (`CHANGELOG.md`, `RELEASING.md`, `README.md`, `LICENSE`, `release_notes/`) live at the repo root, outside the Xcode-synchronized `Imager/` source group. They are visible in Xcode under the `Documentation` group but are not compiled into the app.
- Tags are annotated (`git tag -a`) so they carry a message and tagger, and can be verified and listed with release metadata.
- Keep one commit per release (`Release <version>`) going forward so each tag anchors to a distinct, accurate point in history.
- Release artifacts are built into `build/`, which is gitignored along with `*.xcarchive`. Nothing produced by step 10 is committed; the release asset on GitHub is the only published copy.
