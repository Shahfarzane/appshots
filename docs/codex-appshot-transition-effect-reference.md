# Codex Appshot Transition Effect Reference

Date: 2026-06-29

## Purpose

Document how the Codex Desktop Appshot preview/transition effect appears to be built, and list the files needed to recreate it in Appshots.

The reference screenshot is:

`/Users/shahin/Desktop/Screenshots/Screenshot 2026-06-29 at 09.21.52.png`

The visible effect is a rounded screenshot preview that fades/dims toward the bottom, with the target app icon centered below the preview and the app name below the icon. The important finding is that Codex does not appear to achieve this by only styling the final screenshot in the renderer. Codex has a native Appshot transition renderer that creates a separate transition snapshot asset.

## Core Finding

Codex separates these assets:

- `screenshotDataURL`: the real captured screenshot for the model/user attachment.
- `transitionSnapshotURL` / `transitionSnapshotDataURL`: a separate polished transition/preview image for the UI animation.

Recreating the effect in Appshots should follow the same split. Do not mutate the full-resolution capture for the model. Generate a dedicated transition snapshot PNG from the screenshot, app icon, app title, destination colors, masks, shadows, and layout.

## Codex Native Evidence

Installed Codex native service:

`/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService`

Codex Appshot resources:

`/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/Resources/Package_Appshot.bundle`

Useful binary-string evidence:

```sh
APP="/Applications/Codex.app/Contents/Resources/plugins/openai-bundled/plugins/computer-use/Codex Computer Use.app/Contents/MacOS/SkyComputerUseService"
strings -a "$APP" | rg -n -C 1 'AppshotCaptureTransition|AppshotCaptureTransitionOverlayWindow|NonanimatedGradientLayer|NonanimatedTextLayer|transitionBackgroundLayer|shadowLayer|containerLayer|shutterLayer|snapshotEffectsLayer|snapshotImageLayer|snapshotMaskLayer|appIconLayer|titleLayer|appshotSnapshotFadeIn|appshotShadowCornerRadius|appshotScreenshotCornerRadius|appshotShadowRadius|appshotShadowYOffset|appshotAppIconFadeIn|appshotTitleFadeIn|transitionSnapshotHeight|destinationFrame|destinationCornerRadius|destinationBackgroundColor|destinationPrimaryTextColor'
```

Important native symbols/strings seen:

- `AppshotCaptureTransition`
- `AppshotCaptureTransitionOverlayWindow`
- `NonanimatedGradientLayer`
- `NonanimatedTextLayer`
- `transitionBackgroundLayer`
- `shadowLayer`
- `containerLayer`
- `shutterLayer`
- `snapshotEffectsLayer`
- `snapshotImageLayer`
- `snapshotMaskLayer`
- `appIconLayer`
- `titleLayer`
- `destinationFrame`
- `destinationCornerRadius`
- `destinationBackgroundColor`
- `destinationPrimaryTextColor`
- `transitionSnapshotHeight`
- `appshotScreenshotCornerRadius`
- `appshotShadowCornerRadius`
- `appshotShadowRadius`
- `appshotShadowYOffset`
- `appshotShadowOpacity`
- `appshotAppIconFadeIn`
- `appshotTitleFadeIn`
- `appshotSnapshotFadeIn`
- `appshotMagicMoveFadeDuration`

These names point to a native AppKit/QuartzCore composition stack:

```text
AppshotCaptureTransitionOverlayWindow
  contentLayer
    transitionBackgroundLayer
    shadowLayer
    containerLayer
      shutterLayer
      snapshotEffectsLayer
      snapshotImageLayer
      snapshotMaskLayer / NonanimatedGradientLayer
      appIconLayer
      titleLayer / NonanimatedTextLayer
```

The gradient/mask layer is the likely source of the bottom fade visible in the screenshot. The icon/title layers explain why the icon and app name are part of the transition image, not just surrounding UI.

## Codex Electron Evidence

Renderer container:

`/Applications/Codex.app/Contents/Resources/app.asar`

Extract the renderer chunks for inspection:

```sh
node - <<'NODE'
const fs = require("fs");
const path = require("path");
const asar = "/Applications/Codex.app/Contents/Resources/app.asar";
const out = "/tmp/codex-app-asar-build";
fs.rmSync(out, { recursive: true, force: true });
fs.mkdirSync(out, { recursive: true });

const buffer = fs.readFileSync(asar);
const headerSize = buffer.readUInt32LE(4);
const jsonSize = buffer.readUInt32LE(12);
const header = JSON.parse(buffer.subarray(16, 16 + jsonSize).toString("utf8"));
const dataStart = 8 + headerSize;
const files = header.files[".vite"].files.build.files;

for (const [name, meta] of Object.entries(files)) {
  if (!name.endsWith(".js")) continue;
  const start = dataStart + Number(meta.offset);
  const end = start + Number(meta.size);
  fs.writeFileSync(path.join(out, name), buffer.subarray(start, end));
}

console.log(out);
NODE
```

Search the extracted chunks:

```sh
rg -n "animationTarget|ComputerUseIPCAppStartCaptureRequest|ComputerUseIPCAppNextCaptureUpdateRequest|transitionSnapshotURL|transitionSnapshotDataURL|screenshotDataURL" /tmp/codex-app-asar-build/*.js
```

Relevant extracted files:

- `/tmp/codex-app-asar-build/main-CE4LBHPy.js`
  - contains the capture handler that sends `animationTarget`, `bundleIdentifier`, `permissionRequestId`, and `requestId` into the computer-use capture worker.
- `/tmp/codex-app-asar-build/worker.js`
  - contains the Appshot capture worker schema and request flow.
  - contains `ComputerUseIPCAppStartCaptureRequest`.
  - contains `ComputerUseIPCAppNextCaptureUpdateRequest`.
  - accepts native updates with `screenshotURL`.
  - accepts completion updates with `transitionSnapshotURL`.
  - converts the screenshot file to `screenshotDataURL`.
  - converts the transition snapshot file to `transitionSnapshotDataURL`.

Key behavior from the worker:

```text
screenshot update:
  screenshotURL -> screenshotPath -> screenshotDataURL

completed update:
  transitionSnapshotURL -> transitionSnapshotPath -> transitionSnapshotDataURL
```

That is the strongest evidence that the UI effect is fed by a separate transition snapshot asset.

## Existing Appshots Files To Wire

These are the current Appshots files involved in recreating the effect.

| File | Current Role | Needed Change |
| --- | --- | --- |
| `/Users/shahin/Code/Github/appshots/Sources/Appshots/AppshotCaptureAnimator.swift` | Current native animation. Creates one borderless `NSWindow`, shows the raw screenshot in an `NSImageView`, adds a white flash, then animates to a small destination. | Replace or extend with a layer-backed transition window that can animate a precomposed transition snapshot and/or render the transition snapshot itself. |
| `/Users/shahin/Code/Github/appshots/Sources/Appshots/AppDelegate.swift` | Owns `AppshotCaptureAnimator`; wires `playCaptureAnimation` and `playPendingCaptureAnimation` to the status item destination point. | Keep the wiring, but pass transition snapshot image/data when available. |
| `/Users/shahin/Code/Github/appshots/Sources/Appshots/AppshotsModel.swift` | Owns pending capture state and starts animation from `.screenshot` events or final records. | Prefer a new transition snapshot event/context field when available; fall back to the raw screenshot. |
| `/Users/shahin/Code/Github/appshots/Sources/AppshotsCore/Model/AppshotCaptureEvent.swift` | Defines capture event shape. It has screenshot path/size, but no dedicated transition snapshot path/size. | Add `transitionSnapshotPath` and `transitionSnapshotHeight` or carry the transition snapshot through `context`. |
| `/Users/shahin/Code/Github/appshots/Sources/AppshotsCore/Model/AppshotContext.swift` | Already has `appIconDataURL`, `transitionSnapshotDataURL`, `transitionSnapshotHeight`, spring response, and damping fields. | Keep these fields. Feed them with the dedicated rendered transition snapshot instead of the full screenshot. |
| `/Users/shahin/Code/Github/appshots/Sources/AppshotsCore/Store/AppshotStore.swift` | Currently sets `transitionSnapshotDataURL` to the same PNG data URL as the real screenshot and computes height from screenshot aspect ratio. | Persist/load a separate `transition-snapshot.png`; set `transitionSnapshotDataURL` from that file. |
| `/Users/shahin/Code/Github/appshots/Sources/AppshotsCore/Model/AppshotRecord.swift` | Persists capture paths, but has no transition snapshot path. | Add `transitionSnapshotPath` as an optional schema-v1-compatible field. |
| `/Users/shahin/Code/Github/appshots/Sources/AppshotsCore/Capture/CaptureCoordinator.swift` | Current coordinator holds request/target/cache state. | Make the transition renderer part of the capture pipeline after first screenshot and before final context emission. |
| `/Users/shahin/Code/Github/appshots/Sources/Appshots/Support/PasteboardWriter.swift` | Writes text and full screenshot to pasteboard. | Do not use the transition snapshot for pasteboard image; keep pasteboard on the full screenshot. |

## New Files To Add

Recommended new files:

| File | Purpose |
| --- | --- |
| `/Users/shahin/Code/Github/appshots/Sources/AppshotsCore/Capture/Transition/AppshotTransitionSnapshotRenderer.swift` | Pure renderer that takes screenshot, app icon, title, destination colors, and sizing options, then writes `transition-snapshot.png`. |
| `/Users/shahin/Code/Github/appshots/Sources/AppshotsCore/Capture/Transition/AppshotTransitionSnapshotStyle.swift` | Constants for card width, corner radius, gradient stops, icon size, title font, shadow radius, and spacing. |
| `/Users/shahin/Code/Github/appshots/Sources/AppshotsCore/Capture/Transition/AppshotTransitionSnapshot.swift` | Small value type with `url`, `pixelSize`, `displayWidth`, `displayHeight`, and optional timing/spring fields. |
| `/Users/shahin/Code/Github/appshots/Sources/Appshots/Transition/AppshotTransitionOverlayWindow.swift` | Optional UI-side overlay window if the current `AppshotCaptureAnimator` becomes too large. |

Use `AppshotsCore` for the snapshot renderer because the transition image belongs in the artifact/context pipeline, not only the menu-bar app UI.

## Transition Snapshot Layout

Target layout inferred from Codex:

```text
canvas
  card screenshot at top
    rounded rect mask
    vertical gradient fade/dim near bottom
    subtle shadow outside card
  app icon centered below card, overlapping lower edge
  app title centered below icon
```

Suggested initial constants:

```text
displayWidth: 232 pt
screenshotCornerRadius: 14 pt
shadowRadius: 18 pt
shadowYOffset: 8 pt
iconSize: 40 pt
iconOverlap: 14 pt
titleTopPadding: 10 pt
titleFont: system semibold 16-18 pt
bottomPadding: 12 pt
gradientStart: 55 percent
gradientEnd: 100 percent
```

Render at backing scale:

```text
pixelWidth = displayWidth * backingScaleFactor
pixelHeight = computedDisplayHeight * backingScaleFactor
```

Use native APIs:

- `NSImage`
- `NSGraphicsContext` or a layer tree rendered into `CGContext`
- `CALayer`
- `CAGradientLayer`
- `CATextLayer`
- `NSWorkspace.shared.icon(forFile:)` or existing app icon data path

## Implementation Shape

1. Capture still produces the full screenshot exactly as today.
2. After the first screenshot exists, render `transition-snapshot.png` using:
   - screenshot image
   - `record.appName`
   - app icon image/data
   - screen backing scale
   - target display width
3. Persist it beside the capture:

```text
capture/
  screenshot.png
  transition-snapshot.png
  appshot.md
  context.json
  metadata.json
```

4. Add optional path to `AppshotRecord`.
5. Set `AppshotContext.transitionSnapshotDataURL` from `transition-snapshot.png`.
6. Emit a capture event as soon as the transition snapshot is ready, or include it in the screenshot event if generated fast enough.
7. Update `AppshotCaptureAnimator` to use the transition snapshot for the visible flight animation.
8. Keep clipboard/model image behavior using the full screenshot.

## Current Gap Summary

Current Appshots animation:

- `AppshotCaptureAnimator` uses one transparent `NSWindow`.
- It uses the raw screenshot as the displayed image.
- It adds a white flash overlay.
- It has fixed corner radius `6`.
- It has a white glow-like shadow.
- It animates the window to `28x28`.

Codex transition:

- Uses a dedicated native `AppshotCaptureTransitionOverlayWindow`.
- Has named layers for background, shadow, container, shutter, effects, image, mask, app icon, and title.
- Uses a gradient/mask layer for the screenshot fade.
- Uses app icon/title as first-class transition layers.
- Returns `transitionSnapshotURL` separately from the screenshot.

## Validation Checklist

- Capturing a window writes both `screenshot.png` and `transition-snapshot.png`.
- `metadata.json` includes the transition snapshot path.
- `context.json` and MCP payload include `transitionSnapshotDataURL`.
- The transition snapshot renders sharp on Retina displays.
- The transition snapshot does not replace the model/pasteboard screenshot.
- The preview/animation shows:
  - rounded screenshot
  - bottom fade/dim
  - centered app icon
  - centered app title
  - no clipped shadow
- First visible animation still starts from the screenshot event path, not after all durable files finish.

## Reverse Engineering Reference Files

Readable reconstruction from earlier Codex/CUA work:

- `/Users/shahin/Desktop/rev/cua-mac-readable/README.md`
- `/Users/shahin/Desktop/rev/cua-mac-readable/client.explained.ts`
- `/Users/shahin/Desktop/rev/cua-mac-readable/native-pipe.explained.ts`
- `/Users/shahin/Desktop/rev/cua-mac-readable/window-result.explained.ts`
- `/Users/shahin/Desktop/rev/cua-mac-readable/prettified-originals/client.js`
- `/Users/shahin/Desktop/rev/cua-mac-readable/prettified-originals/native-pipe.js`
- `/Users/shahin/Desktop/rev/cua-mac-readable/prettified-originals/window_result.js`

These files explain the shared Skyshot/native bridge path. The transition-specific evidence is stronger in the installed native service strings and extracted `app.asar` chunks above.

## Implementation status (2026-06-29)

The split is now implemented in Appshots with the same screenshot / transition-snapshot
separation Codex uses. Final file and field names:

- **Renderer (pure, thread-safe, no AppKit):**
  `Sources/AppshotsCore/Capture/Transition/AppshotTransitionSnapshotRenderer.swift` draws the
  card into a `CGContext` bitmap (rounded screenshot + shadow, bottom gradient fade, centered app
  icon overlapping the card's lower edge, centered app title via CoreText) and encodes PNG with
  `CGImageDestination`.
- **Layout / style constants:**
  `Sources/AppshotsCore/Capture/Transition/AppshotTransitionSnapshotStyle.swift`
  (`AppshotTransitionSnapshotStyle.default`, `displayWidth` 232 pt) — shared by the offscreen PNG
  renderer and the live UI overlay. Its `layout(forScreenshotPixelSize:)` returns the canvas size
  and card/icon/title rects in points.
- **Value descriptor:**
  `Sources/AppshotsCore/Capture/Transition/AppshotTransitionSnapshot.swift`
  (`url`, `pixelSize`, `displayWidth`, `displayHeight`).
- **Persistence:** `AppshotStore.save(...)` renders `transition-snapshot.png` beside the capture
  best-effort (a render failure logs via `AppLog.store` and leaves the path nil — the capture
  never fails). `AppshotRecord.transitionSnapshotPath` is an optional, schema-v1-compatible
  field (`transitionSnapshotURL` computed accessor).
- **Context:** `AppshotContext.transitionSnapshotDataURL` is fed from the rendered
  `transition-snapshot.png` (falling back to the screenshot data URL only when no transition PNG
  exists); `transitionSnapshotHeight` is read from the transition PNG's real pixel height divided
  by the render scale, falling back to the screenshot-aspect computation. The full-res
  `screenshot.png` still feeds the model and clipboard and is never mutated.
- **Capture event:** `AppshotCaptureEvent` carries optional `transitionSnapshotPath` /
  `transitionSnapshotHeight`.
- **Live animation:** `Sources/Appshots/AppshotCaptureAnimator.swift` (with
  `Sources/Appshots/Transition/AppshotTransitionOverlayWindow.swift`) builds a layered
  composition from `AppshotTransitionSnapshotStyle` (rounded screenshot layer, shadow layer,
  bottom gradient, app icon layer, title `CATextLayer`) flying to the status item, matching the
  rendered PNG.
