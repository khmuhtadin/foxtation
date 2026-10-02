# Releasing

1. Bump `CFBundleShortVersionString` (and `CFBundleVersion`) in `Resources/Info.plist`.
2. Build the disk image. This also writes the new version and checksum into
   `packaging/homebrew/foxtation.rb`:

   ```sh
   scripts/make-dmg.sh
   ```

3. Commit, tag and publish the release with the DMG attached:

   ```sh
   git commit -am "Release 0.2.0"
   git tag v0.2.0
   git push origin main v0.2.0
   gh release create v0.2.0 dist/Foxtation-0.2.0.dmg --title "Foxtation 0.2.0" --generate-notes
   ```

4. Update the tap. Copy `packaging/homebrew/foxtation.rb` to `Casks/foxtation.rb`
   in the [`khmuhtadin/homebrew-tap`](https://github.com/khmuhtadin/homebrew-tap)
   repository and push it. Users then get it with `brew upgrade --cask foxtation`.

## Signing

Release builds are ad-hoc signed and not notarized, so macOS blocks the first
launch of a downloaded copy (the README explains how to allow it; the Homebrew
cask clears the quarantine flag itself). With an Apple Developer ID the build
can be signed with `FOXTATION_SIGN_IDENTITY="Developer ID Application: …"` (plus
`--options runtime --timestamp` in `build.sh`),
then notarized with `xcrun notarytool submit` and `xcrun stapler staple`.
