# Honbako App Icon

The app and installer share an opaque 1024 × 1024 PNG. iOS applies the outer icon mask.

- App asset: `Aidoku/App/Resources/Assets.xcassets/SumiIcon.appiconset/SumiIcon.png`
- Installer asset: `recommendations/public/install/icon.png`
- Created with the built-in image generation tool, then resized to the required app-icon dimensions.
- Lettering: the single Traditional Chinese character **漫** (U+6F2B).
- Cover treatment: matte black frame and binding, inset printed manga face, generous continuous inner corners following the system icon shape.
- The previous Build 8–10 artwork was the edit target. A private iPhone screenshot was used only as a visual reference for corner masking and is not included in this repository.

## Generation Prompt

Use case: precise-object-edit
Asset type: production iOS app icon artwork, opaque full square.
Input image 1: existing Honbako manga-cover icon, edit target.
Input image 2: user's iPhone screenshot, visual reference ONLY showing the corner-mask problem. Do not reproduce the screenshot, wallpaper, neighboring app, or phone.

Primary request: Keep the thick matte black manga-cover frame and manga print aesthetic, change the text to ONE large character "漫", and make the inner white printed-paper opening have generously rounded continuous corners CONCENTRIC with the iPhone app-icon mask.

Corner geometry is essential: the current white opening's nearly square corners look wrong after iOS rounds the outside. The new white opening should be an inset soft squircle/continuous rounded rectangle, with much larger inner curves. Imagine the outer system squircle has been inset by the black frame thickness, so inner and outer curves follow each other with an even substantial band of black around every corner. At 1024 square, printed paper opening is inset roughly 72–80 pixels from each side, and its inner corner curvature is generous, visually equivalent to a 160–180 pixel radius, smoothly continuous rather than small corner rounding. Keep the manga artwork, panel rules and speed lines entirely clipped inside that rounded paper opening. At the corner areas, there must be plenty of matte black material between the opening and the future system mask.
The actual artwork canvas must remain full bleed, filled with opaque near-black right out to all four square corners. Do not bake in transparent corners, a surrounding wallpaper/background, a separate floating squircle, or a mockup. The system will apply the outer mask.

Text (verbatim): "漫" (U+6F2B). Exactly ONE character. Remove "畫" completely. Enlarge and optically center "漫" in the inset paper panel, occupying around 65–70 percent of the artwork width with clear breathing room. Correct water-radical 氵 on left, 曼 structure on right. Heavy confident black brush manga-title lettering, clean structural strokes, readable at Home Screen size.
Preserve sparse manga panel borders, speed lines and halftone around the edges of the white paper, secondary to the one bold glyph. Restrained printed paper texture. Keep the smooth matte black binding, subtle edge depth and a restrained crease at the left spine; no aged leather, scratched chrome, heavy gloss, extra text, letters, numbers, faces or props.
Output exactly one finished square app-icon artwork, not a comparison sheet or phone rendering.

