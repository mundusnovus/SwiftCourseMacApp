# Swift: Zero to Hero for the Mac

A native Mac app by Asteria Technology with the whole Swift: Zero to Hero course: 161 lessons in 34 modules, from
your first line of Swift to shipping apps for macOS and iOS. Exercises compile and run on your own Mac with Apple's
Swift compiler, so your code never leaves the computer and the course works offline.

The course is the same one as on [Asteria Learn](https://learn.asteria.technology). It is exported from the MNLearn
repository into `Resources/course.json`.

## Version 26.11.1: the Asteria 26 look

Aqua on night with heavy for highlights. The accent is deep aqua `#00826B` in light and aqua `#00FFD3` in dark, so
tinted text keeps 4.5:1; labels on an accent fill use `onAccent`. Titles are SF Pro; Asteria Pixel is only for the
word "Asteria". The new icon is an Icon Composer document, `Resources/AppIcon.icon`, with dark, clear and tinted
versions; `tools/build-app.sh` compiles it with `actool`, and `Resources/AppIcon.icns` is the flat fallback.
`tools/make-icon.py` regenerates the icon's layers.

For screenshots, `ZTH_SCREENSHOTS=1 ZTH_APPEARANCE=dark` (or `light`) sizes the window and picks the appearance
without changing the Mac's own setting.

## What you need

- macOS 26 or later.
- Apple's free Command Line Tools, or Xcode, for the compiler. The app offers to install them if they are missing.

## Building

```bash
swift build
swift run ZeroToHero
```

To check the runner against every lesson (each solution must pass, each starting code must fail):

```bash
swift run ZeroToHero --self-test
```

## Making a release

```bash
tools/build-app.sh
```

This builds `build/Swift Zero to Hero.app` and `build/Swift-Zero-to-Hero-<version>.dmg`. It signs with the first
"Developer ID Application" certificate in your keychain (or `SIGN_IDENTITY`), with the hardened runtime.

### Signing and notarizing

Store your notary credentials once, with an app-specific password from account.apple.com:

```bash
xcrun notarytool store-credentials asteria --apple-id <your Apple Account> --team-id <your team>
```

Then build with `NOTARY_PROFILE=asteria tools/build-app.sh`. The DMG and the app are notarized and stapled, so they
open on any Mac without a warning.

### Mac App Store

```bash
STORE=1 UPLOAD=1 tools/build-app.sh
```

This builds the sandboxed App Store version into `build/appstore/`, signs it with your "Apple Distribution" and
"3rd Party Mac Developer Installer" certificates and the "Swift Zero to Hero Mac App Store" provisioning profile, and
uploads it to App Store Connect through Xcode (sign in to Xcode with your Apple Account first). Each upload needs a new
build number: the script uses the number of commits, so commit before uploading.

In the App Sandbox, macOS does not let the app run a program it has just compiled, so the App Store version runs
exercises with the compiler's interpreter instead. Check it still passes everything by signing a copy of the app with
the sandbox entitlement and running `--self-test`.

Screenshots for the store: `ZTH_SCREENSHOTS=1` opens the window at 1440 by 900 points and runs code lessons as soon as
they open.

## Updating the course

In MNLearn:

```bash
node tools/export-app.mjs ../SwiftCourseApp/Resources/course.json ../SwiftCourseApp/Resources/solutions.json
```

Then run the self-test again.

## Licence

The Asteria License. See [LICENSE](LICENSE).
