# Honbako App Icon

The app and installer share an opaque 1024 × 1024 PNG. iOS applies the outer icon mask.

- App asset: `Aidoku/App/Resources/Assets.xcassets/SumiIcon.appiconset/SumiIcon.png`
- Installer asset: `recommendations/public/install/icon.png`
- Created with the built-in image generation tool, then resized to the required app-icon dimensions.
- Lettering: Traditional Chinese **漫畫** (U+6F2B, U+756B).
- Cover treatment: thick matte black bound-cover frame, subtle spine crease and inner contact shadow, with an inset printed manga face.

## Cover Transformation Prompt

The previous manga-panel artwork (Build 7) was used as the edit target.

Use case: logo-brand / precise-object-edit
Asset type: production iOS app icon, one opaque full-bleed square.
Input image: the existing Honbako manga icon. It is the edit target.
Primary request: Turn this into a miniature physical manga COVER with a thick black skeuomorphic cover border, keeping the exact bold traditional "漫畫" lettering and the existing manga panel/halftone aesthetic.
Change the outer treatment: a substantial continuous rich black bound-cover rim wraps all four sides of the image. It must read as the thickness and binding of a real printed manga cover, not as another thin manga panel rule. The black rim is broad, about 5–7 percent of the canvas width, with a very subtle bevel and soft inner contact shadow. The left edge can read as a slightly thicker bound spine with a restrained embossed groove. Inside this black cover frame is the white printed artwork, with very slight paper warmth. The cover fills the square canvas, straight-on and upright; no floating book on a separate backdrop, no tilted perspective, no hand or props. Keep the dark binding frame continuous into the square canvas corners so the system app-icon mask can trim them naturally. The inner printed-cover opening can have modest physically rounded corners. No outer pre-masked squircle or transparent corners.
Preserve the current central black brush manga title lettering: "漫" above "畫", Traditional 漫畫, with correct structure. Scale the artwork in slightly to give the new broad black frame breathing room; both glyphs remain large and fully visible. Preserve the surrounding manga panel template, speed lines and sparse halftone, but keep them secondary to the title.
Materials: near-black matte laminated cover edging, crisp ink, subtle realistic depth through fine edge highlights and inner shadows only. Avoid shiny plastic or metallic chrome. Strong black and white contrast, clean at small Home Screen sizes.
Text (verbatim): "漫畫", and no other text. Do not substitute 漫画. No Latin letters, numbers, author line or added branding.
Output: exactly one finished square icon artwork, no comparison sheet, no mockup, opaque background.

## Material Refinement Prompt

The first cover transformation was used as the edit target.

Use case: precise-object-edit
Asset type: final iOS manga reader icon.
Edit this candidate with one material correction only. Keep the exact layout, thick continuous black cover border, inset white printed manga panels, large stacked Traditional Chinese "漫畫" lettering, straight-on square composition, and spine position.
Replace the aged leather appearance of the black border with clean smooth matte black printed cover stock, like a new manga paperback. Remove pebbled leather grain, worn white scratches, chrome-like outlines, and raised antique spine bands. Keep just a subtle soft edge bevel, a restrained binding crease down the left, and the gentle inner contact shadow that gives the cover physical depth. The black border remains thick and dark, with only a very faint broad satin highlight; it should feel like a tactile manga cover, never a metallic or leather frame.
The paper artwork remains white with very subtle print texture; preserve the correct two characters "漫畫" and all their strokes. No new text, no branding, no added objects.
Keep black material continuous into all four square canvas corners; opaque full-bleed square with no pre-masked transparent corner cutouts. This is a production icon, not a book mockup on a background.

