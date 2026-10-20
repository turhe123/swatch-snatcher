# SwatchSnatcher — specification

**Tagline:** Pick any color on screen with a magnifier loupe, then copy it as HEX, RGB or SwiftUI code and keep a palette.

**Category:** Screen & OCR

**Inspired by (paid):** Sip ($9.99 one-time)

**Frameworks:** SwiftUI, AppKit, CoreGraphics, ScreenCaptureKit, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

What the paid app does: Sip is a well loved color picker for designers and developers, sold on the Mac App Store and its own site at around 9.99 dollars one-time after earlier subscription experiments, with a long run of five star reviews and frequent mentions in best Mac apps for designers lists. It picks colors anywhere on screen, copies them in many formats and stores palettes. Our free clean-room version covers the core loop.

Feature set: A global hotkey launches a magnifier loupe that follows the pointer. Click to pick, Escape to cancel. The picked color is copied to the clipboard in the chosen default format and added to a history of the last 50 colors. Formats: HEX, RGB, HSL, and a SwiftUI Color initializer string plus an NSColor string. Users can pin colors into named palettes, copy any swatch from the list again, and export a palette as a plain text list. A WCAG contrast checker compares any two chosen swatches and shows the ratio with pass or fail for body text and large text.

UI spec: MenuBarExtra with a drop symbol. The popover shows the current default format picker, a grid of recent swatches, a Pick Color button with the hotkey shown, and a palettes section with simple add and rename controls. Clicking a swatch copies it and flashes a checkmark. The Settings window has the global hotkey recorder, default format, whether to close after one pick or stay in continuous mode, and launch at login. The loupe is a borderless circular window of about 150 points showing a nine by nine grid of magnified pixels with the center pixel outlined and its HEX value in a label below. Empty state: the history area says no colors yet, press the hotkey to pick one.

Technical approach: Request Screen Recording permission through CGPreflightScreenCaptureAccess and CGRequestScreenCaptureAccess. While the loupe is active, grab a small region around the pointer using a SCScreenshotManager capture of the display with a source rect, or CGWindowListCreateImage on older paths, refreshed on mouse moved events from a global NSEvent monitor and a timer at 30 frames per second. Read the center pixel from the bitmap in the display color space and convert to sRGB. The hotkey uses a Carbon RegisterEventHotKey wrapper. History and palettes are Codable arrays saved as JSON in Application Support. Launch at login uses SMAppService.

Edge cases and error handling: On multi-display setups with different scale factors, compute the capture rect in pixels per screen. If permission is denied, show an explanation and a button to the Privacy pane rather than picking black. Wide gamut displays are converted to sRGB and the user is told which space is used. Cap history at 50 and remove duplicates by moving them to the front. Handle Escape and clicking outside all displays by ending the session cleanly and restoring the normal cursor. Target about 450 lines of Swift.
