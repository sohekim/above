# Above — Product & Market Strategy

*Prepared 2026-11-23. Based on a full read of the codebase (TestFlight build 2, commit d0bd1c7) and market research. Figures from third-party estimators (Adapty, Appfigures, ScreensDesign) are rough, order-of-magnitude numbers.*

---

## 1. The short version

**What you have:** a beautifully designed, private, 10-second daily ritual. The craft is real: editorial typography, the moving sky circle, widgets, and a calendar that gets more beautiful the more you use it. It is the kind of app Apple editors like.

**Why it won't go viral as-is:** nothing ever leaves the phone. There is no share action, no export and no recap, so the most beautiful thing the app makes (a month or a year of moving sky circles) is never seen by anyone who doesn't already have the app. There is also no measurement, so you can't tell what works.

**The thesis:** *"One look up a day. Watch your year fill with sky."* Keep the private ritual exactly as calm as it is. Then add three things:

1. **An artifact made to be shared.** A 9:16 "month of sky" reel and an end-of-year grid, sized for TikTok, Reels and Stories, with a subtle wordmark.
2. **A better trigger.** A reminder timed to *your* sunset instead of a fixed 6 PM, plus one-press capture from Control Center, the Lock Screen or the Action button.
3. **A compounding goal.** "365 skies in 2027". Launch on New Year, when journaling intent peaks and when Locket launched.

**Be realistic about scale:** a private journal does not become Locket. Locket-scale growth needs a friend loop, which is optional and comes in Phase 3 here. The realistic first win is a beloved, Apple-featured indie app with steady creator-led TikTok growth. That is very achievable and a good business at this cost base: no servers, one developer.

---

## 2. Product audit

### 2.1 What's strong (keep it)
- **The ritual is small and specific.** Ten seconds, once a day, and only today. That rule is what makes it a ritual instead of another camera roll.
- **The motion.** The looping circle is the app's signature. No direct competitor I found lists video or animated skies in their App Store listing.
- **The editorial calendar.** The Year view filling with circles is emotionally powerful, and it is the payoff of the habit.
- **Private by design.** No account, no tracking, no ads. That is a selling point for this audience (wellbeing, anti-feed).
- **Widgets already exist** (today, one week, two weeks, poster). That matters because widgets are the home-screen channel that drove Locket's growth.

### 2.2 What's holding it back

| Area | Issue | Impact |
|---|---|---|
| **Distribution** | No share, export or recap anywhere. | Zero organic loop. Every install has to be paid or press-driven. |
| **Trigger** | A fixed 6 PM reminder, with notification permission asked on first launch before the user has seen any value. | Lower opt-in rate. 6 PM is dark in winter and misses sunset in summer. |
| **Friction** | Open app → find today → tap → camera → tap → wait 10 s. | Every step costs daily completions. |
| **Payoff** | The calendar is the reward, but the app never celebrates it: no "first full week", "month complete" or "30 skies". | No emotional peaks, and nothing to share at those peaks. |
| **Trust** | No sync or export. The support page tells users to rely on device backups. | Diary apps die on data-loss stories, as in 1 Second Everyday's reviews. It also blocks switching phones. |
| **Identity** | The app, wordmark, website and widgets say **Above**, but leftovers from a brief rename still say **LookUp**: the README, the icon filename and the poster drafts. LookUp is also the name of your separate Mac movement-break project. | Mixed names in screenshots and the listing weaken the brand. Clean the leftovers up before making marketing assets. |
| **Choice overload** | 3 month designs, 6 backgrounds, 7 ink colors and 3 widget styles before the core loop is proven. | Adds no retention or virality. Good later as premium, but not the launch story. |
| **No analytics** | You can't measure D1/D7/D30 retention, reminder opt-in or capture completion. | You'll be guessing about everything below. |

---

## 3. Engineering audit (issues that affect the product)

**Ship-blockers**
1. **Widgets are empty on TestFlight and App Store builds.**
   - `WidgetBridge.swift:14` reads app group `group.com.above.skyjournal`.
   - Both `.entitlements` files were changed to `group.com.app82.above.skyjournal` in commit d0bd1c7.
   - Result: `containerURL` returns nil, so the snapshot is never written and widgets always show empty circles.
   - This is a one-line fix, but it must ship before any widget-led marketing.
2. **Storage growth.**
   - I ran the real `SkyGIFEncoder` on a slowly drifting demo sky and got **~4.8–5.5 MB per day, about 1.8 GB per year**. Real camera noise will likely be worse.
   - HEVC video at the same size would be roughly 10× smaller.
   - Recommendation: store HEVC MP4 (or HEIC sequence) as the master, render the GIF only on export, and keep the JPEG poster for thumbnails. This also makes reels and iCloud sync practical.
3. **Camera permission string says "Take a photo of the sky"**, but the app records video. Fix it for review accuracy.

**Quality and performance**
4. **Full-size JPEGs are decoded synchronously inside `body` for every calendar cell.**
   - `store.image(entry)` is called 17 times across the views. The Year view can do up to 365 disk reads per render.
   - A 60-second `Timer` re-renders the whole calendar each minute.
   - Add an in-memory thumbnail cache (NSCache of ~120 px images) before users have hundreds of entries.
5. **The 5 fps, 480 px GIF looks like a slideshow** once it's shared at phone resolution. For shareable reels, capture at native frame rate and keep 720–1080 px.
6. **DemoSkies (5.4 MB of PNGs) ship in the Release bundle** even though seeding is Debug-only. Move them to a Debug-only resource.
7. **All the code is in one 1,631-line `AboveApp.swift`**, and styles are passed around as strings ("Month v1", "Month v2"). That's fine for a prototype, but split Store, Camera, Calendar and Settings before adding sharing, sync and paywall.
8. **Light mode is forced, and there is no localization.**
   - Localization is a cheap reach win.
   - Japan and Korea have strong cultures of aesthetic journaling and sky photography. That is my judgment, not measured, but worth testing with localized metadata first.

---

## 4. Market

### 4.1 Competitive map

| Segment | Players | What it means for Above |
|---|---|---|
| **Direct: sky diaries** | Sky Palette (photo palette, streaks, recap, PDF book, share cards, sunset alerts), Everysky (live photo only, world sky map, golden-hour alert), Skry (astrology-style "sky readings", $39.99/yr). All are new and tiny. | The concept is already taken. **Differentiate on motion, widgets and design quality**, not on the idea. Sky Palette already has recap, export and alerts, so those are table stakes, not differentiators. |
| **Video/photo-a-day** | 1 Second Everyday (10M+ users claimed, ~$200–250K/mo est., $49.99/yr), Day One ($49.99–74.99/yr), Apple Journal (free; iOS 27 adds streaks) | Proves people pay ~$50/yr for "my life, compiled". Apple adding streaks makes basic habit tracking table stakes. |
| **Social daily-photo** | BeReal (peaked at 73.5M users in 2022 and declined), Locket (91M+ installs, 9M+ DAU claimed, profitable), Retro (~1M active, $21M Series A) | The daily prompt alone decays. **What lasts is a personal payoff plus a friend loop on the Home Screen.** |
| **Anti-doomscroll** | touch grass (~50K users on launch day, no ads), Opal ($10M+ ARR), Focus Friend (#1, then #48 two weeks later) | One-sentence hooks shown in screen recordings go viral. Spikes without retention collapse. |
| **Sky utility** | CloudSpotter (Cloud Appreciation Society, $39.99/yr), SkyCandy and Alpenglow (sunset forecasts, alerts paywalled) | Sunset-timing alerts are a feature people already pay for. |

### 4.2 Tailwinds
- **Gen Z going analog and rebranding mindfulness.** Talker Research (2026) reports 63% of Gen Z intentionally unplug. Being "anti-feed" is a selling point.
- **Wrapped-style recaps are the strongest sharing mechanic there is.** Spotify Wrapped 2025 had 500M+ shares on day one, and BeReal, Retro and Locket all copied the pattern.
- **Apple rewards nature apps with strong design.** 2026 Design Award winners include Moonlitt (moon phases, Liquid Glass), Tide Guide (sky-matched palette) and grug (a small daily ritual). Above fits this profile closely.
- **New platform surfaces:**
  - iOS 27 extra-large (4×6) widget, a natural fit for a month grid
  - Control Center and Lock Screen controls (iOS 18+)
  - LockedCameraCapture
  - free on-device Foundation Models
  - Liquid Glass tinted widgets

### 4.3 Headwinds
- The category is niche and the concept is easy to clone. Sky Palette, Everysky and Skry already have.
- Category D30 retention is about 3–8%.
- Apps launched in 2025 or later earn only ~3% of subscription revenue (RevenueCat SOSA 2026). The market is crowded and attention is expensive.
- On TikTok, "watching sunsets" is grief slang. Avoid that phrase in copy.

---

## 5. Strategy

### 5.1 Positioning
- **Category:** a daily sky diary. "Daily sky" and "sky diary" are high-intent keywords with weak competition. Don't compete on "mindfulness" or "journal" head terms.
- **One-line hook:** *"Ten seconds of sky, every day. Watch your year fill up."*
- **Proof points:**
  - It moves (living skies, not photos)
  - It lives on your Home Screen
  - It's private (no account, no feed)
- **Name.**
  - Keep **Above** as the brand. LookUp belongs to your separate Mac project, so remove it from this repo: the README, the icon filename and the poster drafts.
  - Use the App Store name **"Above: Daily Sky Diary"** (22 chars), with subtitle "Ten seconds of sky, every day".
  - "Above" alone is too generic to rank in search, so the keyword suffix does the ASO work. Make "look up" the call to action in copy ("Look up. Ten seconds."), not the name.
  - Then make the display name, wordmark, website, widgets and copy consistent.

### 5.2 The growth loop

```
Sunset-timed nudge ─▶ 1-press capture ─▶ circle lands in calendar
        ▲                                         │
        │                          milestones (7 / 30 / month complete / 100)
        │                                         ▼
 new user installs ◀── watermark + "made with Above" ◀── shareable reel / grid
```

**Viral mechanics, ranked by expected impact for effort:**

1. **Month Reel (high impact, medium effort).**
   - Auto-generate a 9:16 video at the end of each month and at "30 skies": the month's circles animate into the grid, then each sky plays for a beat. Use your editorial type.
   - Share straight to Stories, TikTok and Reels.
   - Free exports carry a small "Above" wordmark; Plus removes it.
   - This matches the existing TikTok format "I looked up every day for 30 days".
2. **"365 skies in 2027" New Year launch (high, low).**
   - The Year view *is* the challenge board.
   - The launch narrative, the press angle and Apple's featuring theme ("New Year, new habits") all line up.
3. **Year Grid poster (high, low).**
   - A static share image of the year view, available any time ("my 2027 so far").
   - The end of December version is your Wrapped.
4. **Global sky moments (medium, low).**
   - Equinoxes, solstices, Cloud Appreciation Day (Sep 12), eclipses, meteor showers.
   - A one-off nudge ("Everyone's looking up today"), plus a special frame on that day's circle.
   - Gives creators and press a dated hook.
5. **Friends' skies (very high, high effort; Phase 3).**
   - Opt-in, up to ~5 friends, built on **CloudKit sharing**, so there is still no Above account or server.
   - A friend's sky appears on your widget, like Locket's widget mechanic.
   - This is the only route to Locket-type numbers, so build it once the solo loop retains.

### 5.3 Retention design
- **Move the trigger to sunset.**
  - Compute local sunset offline with a solar algorithm. Then location is coarse and on-device only, or the user picks a city, so no WeatherKit is needed.
  - Default to "20 minutes before sunset", with "fixed time" kept as an option.
  - The copy changes daily: "Sunset in 20 min. Look up."
- **Ask for notifications after the first capture**, not on first launch. Frame the ask as "Want a nudge before tomorrow's sunset?"
- **One-press capture.**
  - A Control Center and Lock Screen **control** (ControlWidget) that opens straight into the camera. This works with the Action button too.
  - Later, a LockedCameraCapture extension. Test it against reports that sessions end at ~10 s.
  - Make the Home Screen widget's "+" go straight to the camera; that deep link already exists.
- **Gentle milestones, not punishing streaks.**
  - "7 skies", "a full week", "30 skies", "first full month", "100 skies".
  - Each one plays a small celebration and offers a share. Missed days stay as empty circles, and nothing resets to zero.
- **First-run "aha" moment.**
  - Welcome → straight into the camera → after the first capture, show the circle animating into the empty year.
  - Then prompt for the widget after the 3rd sky.
- **Trust.**
  - Add free iCloud sync (CloudKit private database) and "Export all" (a ZIP, plus a video of the year).
  - Don't paywall backup. Data-loss fear stops people committing to a 365-day habit.

### 5.4 Monetization
Go freemium, and never paywall daily capture.

| Free | Above Plus |
|---|---|
| Daily capture, note, calendar, one widget style, iCloud sync, monthly reel *with* wordmark | Reels and posters without wordmark, extra reel and poster styles, Year Grid poster at full quality, all widget styles (including the iOS 27 extra-large), all palettes and month designs, on-device monthly "sky letter" (Foundation Models) |

- **Price:** $2.99/mo · **$24.99/yr** · **$49.99 lifetime**.
  - The niche median is about $35–50/yr. Going slightly lower suits an impulse, design-led buyer.
  - Lifetime pricing fits an app with no server costs.
- **Trial:** offer a long trial (14+ days), because longer trials convert best (RevenueCat: 17–32 days ≈ 42.5% median). Put the upgrade prompt at the first Month Reel, which is a moment of high emotion.
- **Hold back the paywall** during any viral spike, as touch grass did. Sharing is worth more than early revenue.

### 5.5 Metrics to install now
Add privacy-friendly analytics (for example TelemetryDeck, which is anonymous and fits the privacy story; update the privacy label and policy). Then track:

- **North Star:** weekly active capturers, meaning users with ≥3 skies in the last 7 days.
- **Funnel:** install → first capture (target ≥70%) → notification opt-in → widget added → day-7 capture.
- **Retention targets:** D1 45%, D7 25%, D30 12%. That's well above the 3–8% category baseline, which is plausible for a 10-second habit.
- **Virality:** share rate among month-completers (target ≥15%) and installs per share.

---

## 6. Roadmap

**Phase 0: Launch-ready (now → mid-December)**
- Fix the app group mismatch (widgets).
- Switch to HEVC master plus a GIF only on export; add the thumbnail cache; drop DemoSkies from the Release build.
- Remove the leftover LookUp references (README, icon filename, poster drafts) so everything says Above; fix the camera usage string.
- Move the notification ask to after the first capture; take first-run users straight to the camera.
- Add analytics and a basic share sheet for a single sky (video and GIF).
- Replace the mock posters with real screenshots; lead with the moving circle and the Year grid.
- **Submit an App Store featuring nomination now.** Apple needs at least 2 weeks' notice, and the theme is a New Year habit launch.

**Phase 1: "365 skies in 2027" launch (late Dec → Jan)**
- Ship v1.0 publicly between Dec 26 and Jan 1.
- Sunset-timed reminders, Control Center and Lock Screen capture control, milestones.
- Month Reel (the first one appears Jan 31 for New Year starters, which gives a natural press beat in February).
- Plus subscription with lifetime option.
- Launch on Reddit (r/clouds, r/CozyPlaces, r/minimalism), Hacker News "Show HN", and X/Threads with a 15-second screen-recording hook.
- Seed 10–20 small TikTok and IG creators in slow-living, study-with-me and journaling ("I'm looking up every day in 2027, day 1").

**Phase 2: Depth (Feb → Jun)**
- iCloud sync and Export all.
- Year Grid poster, global sky moments (the Mar 20 equinox is the first big beat), localized metadata for JP, KR, DE, FR and ES.
- iOS 27 extra-large widget, Liquid Glass tinted widget polish.
- On-device "sky letter" monthly reflection (Plus).

**Phase 3: Friends (Jun → Sep)**
- Opt-in friend circles on CloudKit sharing, with friends' skies on your widget and a "same sky, same minute" moment.
- Build it only if solo D30 is at least ~12%. Otherwise the friend loop just amplifies churn.
- Big beat: **Cloud Appreciation Day, Sep 12**. Reach out to the Cloud Appreciation Society (~60K members).

---

## 7. Risks & honest calls
- **Ritual fatigue.** The BeReal pattern shows the daily prompt alone decays, so the payoff (reels, year grid, milestones) has to arrive before week 3.
- **Clones.** Sky diaries are trivial to copy. Your moat is taste, platform polish (Apple featuring) and, later, the friend network.
- **Scope creep in customization.** Hold the palettes and month designs for Plus and stop adding more until retention data exists.
- **Privacy brand vs analytics and social.** Keep both opt-in, describe them plainly, and keep "no account" true by using iCloud.
- **Claims.** The EPA "90% indoors" figure is US-only and from 1980s studies. Keep the scope caveat in any press copy. The UCSF "awe walks" study (n=60) is supportive but small; don't overclaim.

---

## Sources (selection)
- Locket: techcrunch.com/2022/01/11 · /2025/08/06 · /2025/11/03
- BeReal: techcrunch.com/2024/06/11 · /2025/04/10
- Retro: techcrunch.com/2026/08/28
- touch grass: revenuecat.com/blog/growth/rhys-kentish-touch-grass-launched-podcast-2026
- Opal: revenuecat.com/blog/growth/kenneth-schlenker-opal-sub-club-podcast
- RevenueCat State of Subscription Apps 2026: revenuecat.com/state-of-subscription-apps-2026
- Spotify Wrapped 2025: techcrunch.com/2025/12/04
- 2026 Apple Design Awards: apple.com/newsroom/2026/06
- iOS 27 widgets: 9to5mac.com/2026/06/08
- LockedCameraCapture: developer.apple.com/documentation/lockedcameracapture
- Featuring nominations: developer.apple.com/app-store/getting-featured
- Competitors: App Store listings for Sky Palette (id6760690705), Everysky (id6789611050), Skry (id6790419436), 1 Second Everyday (id587823548), CloudSpotter (id1314437708)
