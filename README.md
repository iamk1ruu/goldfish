# Goldfish

**Teach the goldfish. Ace the exam.**

Goldfish is an iPhone study app where you learn a chapter by teaching it to a cartoon goldfish. The fish knows only what you write for it. It takes a hidden exam using nothing but your explanation, and when it gets a question wrong, Goldfish shows the sentence of yours that misled it, or tells you that you never taught that point. The fish forgets everything overnight, so each review starts with you explaining the chapter again from memory. Your own unaided answers, not the fish's score, decide what you have mastered.

Built for the Google #BuildHybridAI 2026 hackathon with Firebase AI Logic.

## How it uses hybrid AI

| Job | Where it runs | Why |
| --- | --- | --- |
| Write the hidden exam from your chapter | Gemini in the cloud (`gemini-3.8-flash`), JSON schema | Needs long context and strong reasoning |
| Play the fish: answer each question from your lesson alone | Apple's on-device model, with Gemini (`gemini-3.5-flash-lite`) as fallback | Free and offline, so you can re-quiz after every edit. A small model is a good pupil, because it needs clear explanations |
| Check that each question is fair | Apple's on-device model only | Runs in the background while you read |
| Write your Report Card | Gemini in the cloud | Summarises the whole session |

Every fish answer shows where it ran ("On this iPhone" or "Cloud"), and each quiz shows a running count. All model calls go through Firebase AI Logic's hybrid inference (`generativeModelSession` with `.hybridModel(primary: SystemLanguageModel, secondary: Gemini)`), in [App/Services/FirebaseModels.swift](App/Services/FirebaseModels.swift).

The fish's answers are graded by code, not by a model. An answer counts only if the fish quotes a 3 to 30 word sentence that appears word for word in your lesson and contains the key term of the option it chose. Anything else counts as "not taught".

## Features

- **Hidden Exam:** the cloud reads a pasted chapter or PDF and writes 6 to 10 concepts with practice, final and Your Turn questions. Code validates every question before it is stored.
- **The Bowl:** one short explanation per concept, with a word limit. Pasting is blocked, and sentences copied from the chapter are flagged and do not count.
- **Pop Quiz:** the fish answers on the phone, one question at a time. Answers for an unchanged lesson are cached.
- **Miss review:** a mix-up highlights your sentence that misled the fish. A gap says what was never taught. The answer is revealed only after two misses.
- **Fresh Water:** when a chapter is due, the fish has forgotten and your old lesson is hidden. You re-teach from memory.
- **Your Turn:** you answer questions the fish never saw. You type your recall first, then choose, and say how sure you are.
- **Mastery Map, Tides and Feeding Time:** concepts are mastered after correct unaided answers on three different days. Reviews are spaced and fitted to your exam date, with a daily reminder tied to a cue you choose.
- **Works offline** once a chapter's exam is stored. The built-in sample chapter works with no connection at all.
- **Friends and teach-offs:** turn on a profile (anonymous, no sign-up), add friends by code, and share a chapter with its hidden exam. In a teach-off you both teach the same chapter, each fish takes every practice question from its own student's lesson, and you see whose explanation worked, idea by idea. Only scores are shared. Lessons never leave the phone.
- **8-bit sounds and haptics** for the fish's answers, mastered ideas and the fire. Made in code by [tools/sound/build-sfx.mjs](tools/sound/build-sfx.mjs), muted by the silent switch.

## Requirements

- An iPhone that supports Apple Intelligence (iPhone 16 or later), on iOS 26 or later, with Apple Intelligence turned on. Without it, the fish runs in the cloud.
- A Mac with Xcode 26.2 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and Homebrew.
- A Firebase project of your own (free, no billing needed).

## Setup

1. **Firebase project.** In the [Firebase console](https://console.firebase.google.com), create a project, open **AI Logic** and enable the **Gemini Developer API**.
2. **Register the iOS app** with your bundle ID (this repo uses `com.kiruu.goldfish`; change `PRODUCT_BUNDLE_IDENTIFIER` in [project.yml](project.yml) to your own). Download `GoogleService-Info.plist` and put it at `App/Resources/GoogleService-Info.plist`. It is git-ignored and must never be committed.
3. **App Check.** Firebase AI Logic requires App Check. Builds of this app use the App Check debug provider, because App Attest needs a paid Apple Developer account. After the first launch, open Settings, long-press the version number to open Diagnostics, copy the debug token, and add it in the Firebase console under **App Check > Apps > Manage debug tokens**.
4. **Friends (optional).** For profiles, sharing and teach-offs:
   - Under **Authentication > Sign-in method**, enable **Anonymous**.
   - Create a **Firestore Database** (the free Spark plan is enough).
   - Deploy the security rules in [firestore.rules](firestore.rules): `firebase deploy --only firestore:rules` with the Firebase CLI, or paste the file into **Firestore Database > Rules**. Without them every friends action is refused.
   - If you turn on App Check enforcement for Firestore or Authentication, the same debug token from step 3 covers them.
5. **Optional: Remote Config** keys for model names and limits are listed in [GoldfishSettings.swift](Packages/GoldfishCore/Sources/GoldfishCore/Settings/GoldfishSettings.swift). Every key has a built-in default.

Without `GoogleService-Info.plist` the app still builds and runs, using a scripted stand-in fish and the sample chapter. The Friends tab then says it needs Firebase.

## Build and run

On the Mac, from the repository root:

```bash
bash scripts/bootstrap-mac.sh   # checks Xcode, installs XcodeGen
bash scripts/test-core.sh       # core logic tests, seconds, no simulator needed
xcodegen generate               # creates Goldfish.xcodeproj
open Goldfish.xcodeproj         # run on a device or Simulator from Xcode
```

To build an unsigned `.ipa` for sideloading, for example with Sideloadly and a free Apple ID:

```bash
bash scripts/build-ipa.sh       # writes build/Goldfish-unsigned.ipa
```

Apps installed with a free Apple ID expire after 7 days.

From Windows, [scripts/remote.ps1](scripts/remote.ps1) copies the source to a Mac over SSH, runs a step, and copies the result back (`-Action test`, `build`, `shots` or `secrets`). [scripts/screenshots.sh](scripts/screenshots.sh) opens each screen in the Simulator with fixture data and saves screenshots.

A GitHub Actions workflow ([.github/workflows/build.yml](.github/workflows/build.yml)) runs the core tests and builds the unsigned `.ipa` on every push. To include Firebase in that build, add the plist as a base64-encoded repository secret named `GOOGLE_SERVICE_INFO_PLIST`.

## Project layout

```
App/                         SwiftUI app
  Features/                  Screens: Today, Chapter, Bowl, Quiz, Miss review, Your Turn, Final exam, Report, Friends, Teach-off, Settings, Diagnostics
  Services/                  Firebase AI Logic, App Check, Remote Config, Auth and Firestore, sounds, PDF text, reminders, network
  Resources/Sounds/          The 8-bit sound effects, generated by tools/sound/build-sfx.mjs
  UI/                        The fish, theme and shared components
Packages/GoldfishCore/       Pure Swift logic, Foundation only, with tests
  Fish/                      Prompt, reply parser, quote check, grader
  Exam/                      Exam drafts, validator, cloud prompts, fair exam check
  Study/                     Review schedule, mastery, quiz picking, report building
  Fidelity/                  The Fish Check: does the on-device model stick to the lesson?
  Scripted/                  Scripted fish and the built-in sample chapter
  Social/                    Share codes, shared chapters, profiles and teach-off scoring
firestore.rules              Security rules for profiles, friends, shared chapters and teach-offs
scripts/                     Mac build, test, screenshot and Windows remote scripts
tools/art/finn8.js           The pixel art for Finn, the source of the app icon and the sprite data
tools/sound/                 The script that writes the 8-bit sound effects
```

The UI follows a Figma education-app kit (purple, Poppins, soft cards), and Finn is an 8-bit sprite. His pixels are defined in [tools/art/finn8.js](tools/art/finn8.js), and the generated Swift sprite data and app icon are committed, so building the app needs nothing extra. Poppins is bundled under the SIL Open Font License.

## Diagnostics and the Fish Check

A hidden Diagnostics screen (long-press the version number in Settings) shows Apple's model availability, where recent answers ran and how long they took, the App Check token, logs, and a time machine for testing spaced reviews. It also runs the **Fish Check**: 20 cell-biology questions asked with a good lesson, a lesson with a fact missing, a lesson with a fact wrong, and an empty lesson. The check measures whether the on-device model answers from the lesson rather than from what it already knows.

## License

[Apache License 2.0](LICENSE).
