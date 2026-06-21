App Store screenshots — manual drop-in
=======================================

Place PNG (or JPEG) screenshots directly in the locale folders:
  fastlane/screenshots/en-US/
  fastlane/screenshots/de-DE/

How fastlane deliver picks them up
----------------------------------
- deliver maps each image to an App Store display type BY ITS RESOLUTION
  (you do NOT need device names in the filename).
- Files upload in sorted filename order, so prefix with numbers to control
  the order shown on the product page, e.g.:
    01_home.png
    02_cards.png
    03_review.png
    04_conversation.png
    05_photo_scan.png

Sizes Apple currently requires (App Store Connect)
--------------------------------------------------
- 6.9" iPhone   — e.g. 1320 x 2868 (portrait) or 2868 x 1320 (landscape).
                  Capture on an iPhone 16 Pro Max simulator/device.
- 13" iPad      — e.g. 2064 x 2752 (portrait) or 2752 x 2064 (landscape).
                  Capture on an iPad Pro 13" simulator/device.
(Other sizes are optional; Apple scales these for smaller devices.)

Tips
----
- Take 3–10 screenshots per size. The same set can live in both en-US and de-DE
  (localize the on-screen text if you want a German-language set).
- To grab frames from a simulator: ⌘S in Simulator, or
  `xcrun simctl io booted screenshot shot.png`.
- These files are committed to git (they are the source of truth) and are
  pushed to App Store Connect by the `release` and `upload_metadata` lanes.
