# Releasing Volume Rocker

## How a release works

1. Move the **Unreleased** notes in `CHANGELOG.md` under a new heading, e.g. `## [0.2.0] - 2026-12-01`, and commit.
2. Tag and push:

   ```bash
   git tag v0.2.0 && git push origin v0.2.0
   ```

3. The **Release** workflow (`.github/workflows/release.yml`) then:
   - builds the Release app (Apple Silicon),
   - signs it with your Developer ID *(if the signing secrets are set)*,
   - creates `VolumeRocker-0.2.0.dmg`,
   - notarizes and staples it *(if the notarization secrets are set)*,
   - publishes a GitHub Release with the DMG and the changelog notes,
   - updates the Sparkle `appcast.xml` on the `gh-pages` branch *(if the Sparkle key is set)*.

   Any step whose secrets are missing is skipped cleanly, and the release still succeeds as an unsigned build.

4. Update the Homebrew cask (`Packaging/homebrew/volume-rocker.rb` → your `homebrew-tap` repo) with the new version and SHA-256.

## GitHub Secrets

Add these at **GitHub → your repo → Settings → Secrets and variables → Actions → New repository secret**.

### Signing (needs a paid Apple Developer account, $99/year)

| Secret | What it is | How to get it |
| --- | --- | --- |
| `MACOS_CERTIFICATE_P12` | Your **Developer ID Application** certificate and private key, base64-encoded | Xcode → Settings → Accounts → Manage Certificates → **+** → Developer ID Application. Then in Keychain Access, right-click the certificate → Export → `.p12` with a password. Run `base64 -i cert.p12 \| pbcopy` and paste. |
| `MACOS_CERTIFICATE_PASSWORD` | The password you chose when exporting the `.p12` | |
| `DEVELOPER_ID` | The certificate's full name | e.g. `Developer ID Application: Jane Doe (AB12CD34EF)`. Find it with `security find-identity -v -p codesigning`. |

### Notarization

| Secret | What it is | How to get it |
| --- | --- | --- |
| `NOTARY_KEY_P8` | App Store Connect API key, base64-encoded | [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/integrations/api) → generate a key with the **Developer** role and download the `.p8` (you can only download it once). Run `base64 -i AuthKey_XXXX.p8 \| pbcopy`. |
| `NOTARY_KEY_ID` | The key's ID | Shown next to the key, e.g. `ABC123DEFG` |
| `NOTARY_ISSUER_ID` | Your issuer ID | Shown at the top of the same page (a UUID) |

### Sparkle updates

Updates are signed with an EdDSA key pair. You create it **once**, on your Mac:

1. Download Sparkle 2.10.1 from [its releases page](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1) (`Sparkle-2.10.1.tar.xz`) and double-click to unpack it.
2. In Terminal, run `bin/generate_keys` from the unpacked folder. It stores the private key in your login keychain and prints the **public key** (44 characters ending in `=`).
3. Put the public key into `VolumeRocker/Resources/Info.plist` as the value of `SUPublicEDKey`, and commit. Until you do, the app shows "Automatic updates aren't set up in this build" in Settings → Updates.
4. Export the private key for GitHub with `bin/generate_keys -x sparkle_private_key`, then add the file's contents as the secret below. Delete the exported file afterwards; it stays safe in your keychain.

| Secret | What it is |
| --- | --- |
| `SPARKLE_PRIVATE_KEY` | The exported EdDSA private key that signs updates. **Back it up in your password manager.** If you lose it, existing users can't receive updates any more. |

Also turn on **GitHub Pages** (Settings → Pages → deploy from branch `gh-pages`, root) so the appcast is served at `https://printmoney.github.io/volume-rocker/appcast.xml`.

## Releasing without a paid developer account

Leave all signing and notarization secrets empty. The workflow builds an **ad-hoc signed** app, and the release notes automatically tell users how to open it (see "Apple could not verify…" in the README). Sparkle updates still work, because their security comes from the EdDSA signature and not from Apple's certificate.

## Releasing from your own Mac

```bash
DEVELOPER_ID="Developer ID Application: Jane Doe (AB12CD34EF)" NOTARY_KEY_PATH=~/keys/AuthKey_ABC123DEFG.p8 NOTARY_KEY_ID=ABC123DEFG NOTARY_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx Scripts/release-local.sh
```

Leave out the variables you don't have, and those steps are skipped. The DMG lands in `dist/`.
