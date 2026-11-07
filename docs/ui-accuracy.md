# Screenshot OCR for UI debugging

## Measured scope

The test uses a generated Chromium settings screen, captured through Ego Lite/CDP. It is browser-rendered screenshot coverage relevant to Playwright workflows; Playwright itself was not used to generate this run. It covers light/dark themes, 12/14/16 CSS px text, and 1×/2× device rendering: 12 screenshots of six layouts with repeated content. Images are 1000×720 or 2000×1440 pixels. Each has 15 annotated labels including Vietnamese names/diacritics, validation errors, HTTP 422, percentages, a monetary value, muted text, and button labels.

DOM text and element rectangles are the reference. mac-ocr runs with `--lang vi-VN,en-US --level accurate --pixels`. Text matching uses NFC and whitespace normalization, preserving case, punctuation, and diacritics. An expected label counts as recovered if it appears exactly within an OCR line. Coordinate checks only include whole-line exact matches and test whether the OCR box center lands inside the DOM label rectangle, allowing 3 CSS px. This does not measure box IoU or click reliability.

| Screenshot scale | Exact label recovery | Box centers inside label |
| --- | ---: | ---: |
| 1× | 89/90 | 89/89 eligible matches |
| 2× | 90/90 | 90/90 eligible matches |

The only mismatch was `Hồ sơ người dùng` → `Hô sơ người dùng` on dark 14 px at 1×. The native 2× capture recovered that label correctly. All annotated validation messages, HTTP status, percentages, and the monetary value matched. These are repeated synthetic labels; the counts must not be presented as general real-app OCR accuracy.

The fixture also has intentionally clipped text and a disabled Save button. DOM checks record these states, and one dark 12 px screenshot was visually reviewed. They are not scored as OCR bug-detection successes: OCR cannot establish whether a control is disabled, recover invisible clipped content, or identify the code causing an error. No real native-app screenshot corpus or measured AI UI-diagnosis comparison has been run.

## Use with Playwright

1. Inspect DOM/accessibility and test assertions first: validation state, disabled controls, overflow, and network/console errors.
2. OCR image-only content or screenshot text when the DOM is unavailable. Use `accurate` and explicit language hints. For small text, try a native device-resolution capture; enlarging an existing bitmap does not restore detail.
3. Use vision on the relevant screenshot region for layout, contrast, clipping, and icons. Relate the finding to DOM/CSS/source before changing code.
4. Rerun the failing assertion and compare the affected screenshot region after the fix.

[Playwright screenshot scaling](https://playwright.dev/docs/api/class-page#page-screenshot-option-scale) supports `scale: 'css'` or `scale: 'device'`. For a viewport screenshot, convert OCR pixels with `cssX = imageX * viewportWidth / imageWidth` and the equivalent Y formula. For cropped screenshots, use the crop's CSS dimensions and add its CSS origin. Full-page screenshots additionally require scroll/document-coordinate handling. Do not blindly divide by `devicePixelRatio`: screenshot APIs can normalize the image to CSS pixels. OCR boxes describe text, not the full clickable control; prefer DOM locators for clicks.

## Reproduce

Requires a built CLI, Python 3, and Ego Lite with `ego-browser`:

```sh
swift build -c release
ego-browser nodejs < tests/ui-accuracy.mjs
python3 tests/ui-accuracy.py
```

Screenshots, DOM references, raw OCR JSON, per-label mismatches, and coordinate results are saved under `/private/tmp/mac-ocr-ui-accuracy`. The generator intentionally uses native CDP screenshots because the Ego screenshot helper normalized the first trial to CSS resolution. The scorer derives coordinate scaling from image dimensions.
