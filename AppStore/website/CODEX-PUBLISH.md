Paste the text below into the ChatGPT Codex thread that publishes honbako.xyz.

---

Please replace the current honbako.xyz site with the finished static site in this folder, using the same site project you deployed to earlier today (the "Duo viewer" version):

/Users/jun/Documents/Codex/Honbako/AppStore/website

- It's plain HTML and CSS with no build step: `index.html`, `styles.css` and the `assets/` folder. Publish the folder as is, with `index.html` at the site root.
- Don't publish `README.md` or `CODEX-PUBLISH.md`. They are notes, not pages.
- Don't add, swap or re-encode any images or videos. Every asset there has been checked: they show only Honbako's original sample stories (character art by Wataobi) and no personal library.
- Keep the existing links: Help and Privacy go to https://missingems.github.io/Honbako/support/ and /privacy/, and "Join the TestFlight" goes to https://testflight.apple.com/join/1PwJ2Bja.
- Save it as a new version so the current one can be restored if needed.

After publishing, open https://honbako.xyz and check:
1. The title is "Honbako" and the hero says "A manga reader for iPhone Duo, iPhone and iPad."
2. Both videos play: the page turn near the top and cover mode near the bottom.
3. The three feature rows show iPhone Duo images, and the "Bring your own AI" row shows the ChatGPT, Claude and Grok icons.
4. At phone width there's no sideways scrolling.

Reply with the version number you published.

---

Update after version 10 (send this part for the next publish): changed files are `index.html`, `styles.css`, `assets/honbako-duo-cover-mode.mp4`, `assets/honbako-duo-cover-mode.webm`, `assets/cover-mode-poster.jpg`, and two new images, `assets/duo-ai-recap.webp` and `assets/ai-recap-detail.webp`. `assets/duo-coaching.webp` is no longer used, so leave it out. Extra checks:
5. "Bring your own AI" shows iPhone Duo split between a manga page and an AI chat, captioned "Example conversation". At 390 px a readable copy of the chat appears under the device; at desktop width it doesn't.
6. The cover-mode video opens on the outer cover (not the reading spread) and is 8.6 s long.
