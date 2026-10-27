# Honbako App Icon

The app and installer share an opaque 1024 × 1024 PNG. iOS applies the outer icon mask.

- App asset: `Aidoku/App/Resources/Assets.xcassets/SumiIcon.appiconset/SumiIcon.png`
- Installer asset: `site/install/icon.png`
- Mode: built-in image generation tool, editing the previous icon, then resized to the required app-icon dimensions.
- Lettering: the single Traditional Chinese character **漫** (U+6F2B), slightly smaller with more white space.
- Background: white manga paper and panel artwork extend to every canvas edge; the outer black border is removed.
- Manga treatment: restrained panel lines, speed lines, and halftone around a clean white center.
- Checked at actual Home Screen size in the iPhone Duo simulator.

## Generation Prompt

Use case: precise-object-edit
Asset type: production iOS app icon, full opaque square.
Input image: current Honbako manga icon, edit target.

Change only two things: remove the thick black outer border completely, and reduce the central character's size slightly (about 10–12 percent smaller than the reference).

The white manga paper and its panel illustrations must now extend full bleed to all four square canvas edges and corners. Remove the entire black surrounding band and the inset rounded white window; there should be no outline around the app icon, no frame, no spine, no bevel, no rim, no rounded rectangle drawn inside the canvas. Continue the white paper and the existing manga panel lines, speed lines and halftone naturally out to the full square edges. The system will supply the outer rounded icon mask. Keep the full canvas opaque, not transparent.

Text (verbatim): "漫", exactly one correct character U+6F2B. Preserve its same bold expressive black brush lettering, same stroke structure and manga title character. Scale that glyph down approximately 10–12% from the reference while keeping it optically centered in both axes. Preserve balanced clear white breathing space above and below and separate the ink from the peripheral panel art. It must remain strong and readable at Home Screen size.

Keep the black-and-white manga print aesthetic, sparse peripheral panel dividers, fine speed lines and restrained halftone. Neutral even white paper, minimal grain. Do not add any new subjects, labels or glyphs.
Output one finished square 1024 × 1024 app-icon artwork; no device mockup, no wallpaper, no outer black border, no outline, no shadow, no transparency.

