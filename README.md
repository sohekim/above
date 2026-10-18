# Above

A small iOS sky diary. Take a moment to look up, record ten seconds of sky through a circular camera preview, and collect a month of photographs.

## Run

Open `Above.xcodeproj` in Xcode 16 or newer and run on an iPhone with iOS 17 or newer. Select your development team in Signing & Capabilities for a physical device. Simulator supports browsing and notes; camera capture requires a real iPhone.

## Current experience

- Cream background, handwritten Above wordmark, bold lowercase month headings.
- Monthly calendar fits the screen; header and grid remain consistently positioned across months. The wordmark is right-aligned; there is no home subtitle or Look up button.
- Tap an empty past or current date to open the camera directly. Tap the sky circle to start a silent ten-second recording; a ring tracks progress. No separate shutter or photo-library import.
- Recordings become 480 × 480 looping GIFs at 5 fps. The diary animates them inside a circle; the calendar uses a still thumbnail. Existing photos remain readable. Reduce Motion shows a still.
- Interrupted recordings are discarded. GIF conversion runs off the main thread; temporary video files are removed.
- Full-screen photo detail with date and a scrollable note.
- Tap the note to edit inline; empty notes show a placeholder. The keyboard's Done key saves and dismisses editing. Photos keep their size while editing.
- Month navigation; no Archive or sharing controls.
- Local storage for images and notes. No accounts or backend.
- First-launch introduction; subsequent launches open the calendar.

The prototype seeds six sample entries once in the current month, using three AI-generated sky images. Existing photos are preserved. Samples can be deleted and are never restored automatically.

## Validation

Built with Xcode 16.4 for iPhoneOS, and run in the iPhone 16 Pro simulator on iOS 18.6. Physical camera recording, progress timing and preview-to-capture matching still need device validation. A synthetic-frame encoder check verifies 50 frames, square dimensions, ten-second playback and infinite looping. Hardware movie encoding is unavailable in this sandbox.

## Copy provenance

The introduction's approximate 90% indoor-time figure comes from U.S. EPA guidance about Americans, rather than a worldwide measurement or a measurement of sky-viewing frequency: https://www.epa.gov/report-environment/indoor-air-quality

## Encoder check (macOS)

Run `swiftc Above/SkyGIFEncoder.swift Tests/SkyGIFEncoderChecks.swift -o /tmp/above-gif-check && /tmp/above-gif-check`. This uses synthetic frames; it does not claim to test camera capture.
