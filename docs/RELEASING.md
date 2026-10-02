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

Builds are signed with a self-signed certificate named **Foxtation** that lives
in the maintainer's login keychain. Because the signature stays the same from
one release to the next, macOS keeps a user's Microphone and Accessibility
permissions across updates. `scripts/make-dmg.sh` refuses to build without it.

**Back it up.** Export it from Keychain Access (My Certificates → Foxtation →
Export, `.p12`). If it is lost, the next release gets a new signature and every
user has to grant both permissions once more.

The app is not notarized, so macOS still blocks the first launch of a
downloaded DMG (the README explains how to allow it; the Homebrew cask clears
the quarantine flag itself). Notarization needs a paid Apple Developer ID:
sign with `FOXTATION_SIGN_IDENTITY="Developer ID Application: …"` plus
`--options runtime --timestamp`, then `xcrun notarytool submit` and
`xcrun stapler staple`.
