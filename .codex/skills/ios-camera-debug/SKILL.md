---
name: ios-camera-debug
description: Debug and implement iOS camera features for the CameraHuman app. Use when working on AVFoundation camera preview, front/back switching, lens capability detection, tab-based camera UI, or device-specific camera behavior across iPhone models.
---

# iOS Camera Debug

Use this skill for camera work in `CameraHuman`, especially when the request touches preview, lens selection, permissions, or hardware capability differences.

## Scope

Primary files to inspect first:

- `CameraHuman/CameraViewController.swift`
- `CameraHuman/SceneDelegate.swift`
- `CameraHuman/RootTabBarController.swift`

Inspect `Info.plist`, storyboard, or related capture code only if the task actually touches permissions, launch flow, or camera startup.

## Workflow

1. Read the camera controller and identify the current state model:
   - active camera position
   - available lens options
   - active input / capture session
   - preview attachment path
2. Distinguish physical lenses from software effects.
3. Confirm whether the UI is promising a capability the hardware does not actually expose.
4. Implement the smallest correct hardware-driven behavior first.
5. After edits, run build verification and inspect any AVFoundation-specific regressions.

## Guardrails

- Do not treat `portrait` as a physical lens. It is a capture effect / processing mode, not a separate front or rear camera device.
- Front camera options must be hardware-driven. If the device exposes only one usable front camera field of view, show a single front mode rather than fake variants.
- Rear camera options must come from discovered `AVCaptureDevice.DeviceType` support, not assumptions about a specific iPhone model.
- If labels such as `0.5x`, `1x`, or `3x` are shown, ensure they map to actual discovered devices.
- Prefer removing misleading camera modes over presenting inaccurate controls.
- Keep preview-first UX. Full-screen camera preview should not be compressed by unnecessary navigation chrome.

## Device Logic

Use `AVCaptureDevice.default(_:for:position:)` or discovery sessions to resolve supported camera devices per position.

Expected reasoning:

- `.builtInUltraWideCamera` -> ultra wide style rear option
- `.builtInWideAngleCamera` -> normal rear camera, or single front camera in many iPhones
- `.builtInTelephotoCamera` -> telephoto rear option
- `.builtInTrueDepthCamera` -> front-facing hardware; do not imply multiple focal lengths unless the device actually exposes them

When behavior differs by phone model, prefer runtime capability checks over hardcoded model assumptions.

## UI Rules

- Tab bar is acceptable for top-level navigation between camera and sound.
- Camera HUD can be inspired by pro-camera apps, but controls must stay truthful to device capability.
- If a button exists for inspection or diagnostics, use it to surface real hardware information rather than guessed labels.

## Validation

After camera edits:

1. Run the repo build verification skill or equivalent `xcodebuild` check.
2. Check for Swift compile errors separately from local Xcode / simulator runtime issues.
3. Verify these states in code and, if available, on-device:
   - permission denied
   - rear camera startup
   - front camera startup
   - lens button rebuilding after position switch
   - preview layer attachment only once

## Project-Specific Notes

- `CameraHuman` currently uses a tab-based root controller.
- Camera work has already hit real confusion around fake portrait/front lens modes; preserve the hardware-truthful approach.
- If `xcodebuild` fails because storyboard tooling or iOS platform files are missing, report that separately from code defects.
