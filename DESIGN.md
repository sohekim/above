# Design decisions

Above is a simple invitation to look up once a day, expressed as an independent magazine or personal diary rather than a dashboard.

## Visual direction

Warm cream paper, black interface, generous whitespace, original bold system sans-serif for month and date headings. A smaller Bradley Hand wordmark provides the handwritten accent. Sky photographs supply the color. No large illustrations, colored action buttons, Archive, or sharing controls.

## Calendar

Circular sky thumbnails on daily dates. The current empty day has a thin outlined plus. Large lowercase month name; consistent reserved heading and subtitle heights keep the calendar from shifting between months. Look up remains fixed at the bottom with a consistent 22-point font. The home screen fits without scrolling.

## Camera

The plus and Look up open the camera directly. Circular live viewfinder, monochrome shutter, arrow-only Back control. The only editorial caption is “Take a moment to look up.” No photo-library import. Capture uses a centered square crop displayed through a circular mask.

## Diary detail

Full-screen presentation, not a stacked sheet. Arrow and text share the left margin; trash aligns to the right margin. Bold date such as “october 7”, followed by “Wednesday, 2026”. Large centered circular photograph. Long notes appear completely and the detail page scrolls.

Tap a note to edit it directly. Empty notes show “A few words about this sky…”. No edit icon or separate note screen. Keyboard Done saves and dismisses, without an extra Done toolbar. The photograph retains its size while editing.

## Introduction

Shown once, with large editorial copy:

“We spend about 90% of our time indoors.”

“There’s still a sky above you.”

Both sentences use the same font size. No “Did you know?” label or source link in the UI. A small supporting line reads “One photo. A little more looking up.” and the action is “Let’s look up ↗”. The statistic’s original U.S. scope is recorded in README.md.

## Remaining validation

Camera capture and exact preview-to-capture crop matching require a physical iPhone. The prototype intentionally has no account, sync service, or distribution signing configuration.
