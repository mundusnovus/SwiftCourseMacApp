# Swift: Zero to Hero for the Mac

A native Mac app by Asteria Technology with the whole Swift: Zero to Hero course: 161 lessons in 34 modules, from
your first line of Swift to shipping apps for macOS and iOS. Exercises compile and run on your own Mac with Apple's
Swift compiler, so your code never leaves the computer and the course works offline.

The course is the same one as on [Asteria Learn](https://learn.asteria.technology). It is exported from the MNLearn
repository into `Resources/course.json`.

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

## Updating the course

In MNLearn:

```bash
node tools/export-app.mjs ../SwiftCourseApp/Resources/course.json ../SwiftCourseApp/Resources/solutions.json
```

Then run the self-test again.

## Licence

The Asteria License. See [LICENSE](LICENSE).
