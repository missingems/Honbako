# Honbako App Icon

The app and installer share an opaque 1024 × 1024 PNG. iOS applies the outer icon mask.

- App asset: `Aidoku/App/Resources/Assets.xcassets/SumiIcon.appiconset/SumiIcon.png`
- Installer asset: `recommendations/public/install/icon.png`
- Mode: built-in image generation tool, editing the previous icon, then resized to the required app-icon dimensions.
- Lettering: the single Traditional Chinese character **漫** (U+6F2B).
- Frame: flat near-black printed border with balanced insets and matching continuous inner corners. No separate side spine, bevel, binding seam, or directional rim lighting.
- Manga treatment: restrained panel lines, speed lines, and halftone around a clean white face.
- Verified at actual Home Screen size in the iPhone Duo simulator.

## Generation Prompt

Use case: precise-object-edit
Asset type: production iOS app icon, one square opaque artwork.
Edit target: the attached current Honbako icon. Fix its uneven apparent spacing and distracting left binding.

Make the frame a CLEAN, FLAT, UNIFORM BLACK PRINTED BORDER. Completely remove the left-side book spine, separate vertical strip, fold, binding seam, offset bevel, raised lip, directional highlight, 3D volume and shadow. There must be no side protrusion. All four sides should have the same near-black color and the SAME visual thickness. No photographic book object or leather material. Think a beautifully printed manga cover in a precise graphic frame.

Geometry: full square 1024 × 1024 canvas, opaque near-black all the way to the square outer edges; iOS will apply its own outside mask. The inset white printed face must be a perfectly centered square continuous rounded rectangle. Its top, bottom, left and right straight-edge insets should all be EXACTLY 64 pixels. White opening bounds at x=64,y=64,width=896,height=896. Use matching continuous inner corner curvature, visually around a 160 pixel radius, following the eventual iPhone outer icon shape. Top and bottom edges of this white face must be equally far from the canvas edge, and the four corner curves must match one another precisely. No perspective or tilt. No rounded black book mockup sitting on a background.

Keep exactly one correct "漫" (U+6F2B). Retain the bold expressive black manga brush title lettering, but make its composition visually centered in both axes. A little more white breathing space than before: glyph occupies roughly 66% width and 66% height of the full canvas; center the solid ink mass, with equal apparent white space above and below. No strokes touching the frame. Clean strong silhouette at app-icon size.
Retain restrained manga panel dividers, fine speed lines, and light halftone dots only near the inner white panel's edges, all clipped by its rounded corners. Keep the central region behind the letter clean. White paper is neutral and evenly lit, with minimal print grain. All lighting and edge treatments must be symmetrical so nothing makes the top border look lighter/thinner than the bottom.
Text (verbatim): "漫". No other glyphs, letters, numbers, branding, or small text.
Output exactly one final flat square app icon artwork; no device, no wallpaper, no shadow outside it, no transparency, no comparison layout.

