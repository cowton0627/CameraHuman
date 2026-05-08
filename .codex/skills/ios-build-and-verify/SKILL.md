---
name: ios-build-and-verify
description: Build and verify the CameraHuman iOS app after changes. Use when validating Swift edits, checking xcodebuild results, separating code errors from local Xcode platform issues, and reviewing git cleanliness before or after implementation.
---

# iOS Build And Verify

Use this skill after meaningful code changes in `CameraHuman`, or before concluding that a feature is done.

## Scope

Default targets:

- project: `CameraHuman.xcodeproj`
- scheme: `CameraHuman`
- repo root: current git top level

## Workflow

1. Check git working tree state before and after changes.
2. Run a deterministic build command for the app.
3. Capture the build log to a file so errors can be searched precisely.
4. Separate true code failures from environment failures.
5. Report only the actionable result.

## Default Commands

Use these commands unless the repo structure changes:

```bash
git status --short
```

```bash
xcodebuild -scheme CameraHuman -project CameraHuman.xcodeproj -destination 'generic/platform=iOS' -derivedDataPath /tmp/CameraHumanDerivedData CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build > /tmp/camerahuman-build.log 2>&1
```

```bash
rg -n "error:|warning:" /tmp/camerahuman-build.log
```

When focusing on the files changed in this app, prefer targeted searches such as:

```bash
rg -n "CameraViewController.swift:.*error:|RootTabBarController.swift:.*error:|SoundViewController.swift:.*error:|error:" /tmp/camerahuman-build.log
```

## Interpretation Rules

- If Swift file compile errors are present, treat them as the primary blocker.
- If the build fails only because `ibtool`, simulator services, or an iOS platform runtime is missing, report that as an environment issue rather than a code regression.
- Do not claim a successful build if `xcodebuild` exited non-zero, even if the edited Swift files appear clean.
- If the worktree is dirty, distinguish your changes from unrelated existing changes.

## Quality Checks

Before finishing, check these:

1. Are new source files tracked or still untracked?
2. Did project wiring change, such as `project.pbxproj` or app launch flow?
3. Did the implementation leave temporary debug code, stale comments, or misleading labels?
4. If a runtime-sensitive feature changed, did the validation cover the likely edge cases?

## Project-Specific Notes

- This repo has previously failed builds because `Main.storyboard` and `LaunchScreen.storyboard` required an unavailable iOS platform in the local environment.
- When that happens, explicitly state the exact failing files and that this is not the same as a Swift compile error.
- Camera and sound work often span multiple new files, so always inspect `git status --short` for untracked additions.

## Output Style

Summarize verification in this order:

1. Build result
2. Whether failures are code or environment
3. Git cleanliness / changed files
4. Residual risk, if runtime behavior could not be exercised locally
