# Above

A small iOS sky diary. Take a moment to look up, record ten seconds of sky through a circular camera preview, and collect a month of photographs.

## Run

Open `Above.xcodeproj` in Xcode 16 or newer and run on an iPhone with iOS 17 or newer. Select your development team in Signing & Capabilities for a physical device. Simulator supports browsing and notes; camera capture requires a real iPhone.

## Current experience

- Neutral off-white calendar home with a neutral off-white header that fills with today’s captured sky poster, a clean sans-serif Above wordmark, and bold lowercase month headings below the calendar. Diary and capture retain a neutral off-white background.
- Monthly calendar fits the screen, including six-row months. Large sky circles, centered weekday labels, no visible date numerals, and a smaller right-aligned wordmark. The calendar sits lower on the page. With today’s sky, the photo header is taller by about 6% of screen height and a month-and-year header sits above the calendar with navigation chevrons on the right. Without today’s sky, a large bold month title sits above the year and two-line caption. No home subtitle or Look up button.
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

## Compare home states

In Simulator, tap the above wordmark to select a sample sky, no sky, or actual saved data. This preview never changes stored photos. On iPhone, the app automatically uses today’s saved sky.

The decorative black starburst appears only beside the caption in the no-sky layout. The captured-sky calendar is bottom aligned above the safe area, and the sky photo fills all remaining space above its header.

All screen backgrounds use the same neutral off-white (98% white), without a yellow tint.

Month / Year controls switch between the existing monthly layout and a scrollable editorial year view. Bold month abbreviations flow inline with day numbers; saved entries replace day numbers with circular sky posters. Year arrows navigate years. Tapping a saved day opens its diary; past or current empty days open capture. Future dates are disabled.

Two additional monthly styles are available from the top selector: Blocks uses an oversized month number with touching black capsule week rows with plain light date numerals for empty days and tightly spaced sky circles without numerals for recorded days; Poster uses an oversized month abbreviation, a ruled month/year header, and bold date numerals. Saved days show sky photos in both styles; navigation and diary/capture actions use the same stored entries. All styles retain the neutral off-white background.

Poster centers the oversized month abbreviation, shows recorded skies without date numerals, and keeps only navigation arrows in the bottom row.
