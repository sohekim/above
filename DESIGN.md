# Design decisions

Above is a simple invitation to look up once a day, expressed as an independent magazine or personal diary rather than a dashboard.

## Visual direction

Warm cream paper, black interface, generous whitespace, original bold system sans-serif for month and date headings. A smaller Bradley Hand wordmark, right-aligned on the home screen, provides the handwritten accent. Sky photographs supply the color. No large illustrations, colored action buttons, Archive, or sharing controls.

## Calendar

White calendar home with a small right-aligned handwritten wordmark. The full-width area above the calendar defaults to pale sky blue and displays today’s captured sky poster once available. It always represents today, even while browsing other months; it refreshes at minute boundaries. A white wordmark with a subtle shadow sits over photographs. Small bold weekday labels are centered above large circular sky thumbnails with tight horizontal spacing. Date numerals are hidden; full dates remain available to accessibility. Empty dates have pale gray circles; today has an outlined plus. The home fits without scrolling, including six-row months. When today’s sky exists, weekday labels and footer copy are lighter, with a 72-point month title. Without today’s sky, the 78-point title and bold 16-point footer return. Both versions reserve the same layout heights. In Simulator, tap above to compare sample-sky, no-sky, and actual-data modes; this does not modify saved entries.

Below the calendar, the month is a large bold lowercase headline. The footer places the bold year on the left, “a little sky to keep / every day.” in two lines at the same 16-point size in the middle, with no decorative icon. Month navigation remains above the calendar. No subtitle, Look up button, Archive or share controls. Tap an empty date to capture.

## Camera

The calendar date opens the camera directly. The circular live viewfinder is the recording button. Tapping it records ten seconds, with a monochrome progress ring around the circle and no separate shutter. The recording becomes a silent looping GIF. Arrow-only Back control cancels incomplete capture. Before recording, the circle contains “tap to keep a little sky”. The caption disappears during recording, leaving the progress ring. There is no text below the circle. No photo-library import. Capture uses a centered square crop displayed through a circular mask. The diary loops the GIF and calendar thumbnails remain still.

## Diary detail

Full-screen presentation, not a stacked sheet. Arrow and text share the left margin; trash aligns to the right margin. Bold date such as “october 7”, followed by “Wednesday, 2026”. Large centered circular photograph. Long notes appear completely and the detail page scrolls.

Tap a note to edit it directly. Empty notes show “A few words about this sky…”. No edit icon or separate note screen. Keyboard Done saves and dismisses, without an extra Done toolbar. The photograph retains its size while editing.

## Introduction

Shown once, with large editorial copy:

“We spend about 90% of our time indoors.”

“There’s still a sky above you.”

Both sentences use the same font size. No “Did you know?” label or source link in the UI. A small supporting line reads “Ten seconds. A little more looking up.” and the action is “Let’s look up ↗”. The statistic’s original U.S. scope is recorded in README.md.

## Remaining validation

Camera capture and exact preview-to-capture crop matching require a physical iPhone. The prototype intentionally has no account, sync service, or distribution signing configuration.
