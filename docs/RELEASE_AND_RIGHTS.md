# Release and content rights

Research date: 26 October 2026. These are engineering release constraints, not legal clearance or a guarantee of App Review approval.

## Reader engine

Honbako currently incorporates Aidoku’s GPLv3 reader. Charging for software is not itself forbidden by the GPL, but recipients must receive the license’s source and redistribution freedoms. Preserve the license, copyright notices, modification notices, and corresponding source. Apple distribution terms, DRM, third-party dependency licenses, and any proposed proprietary Pro components require a qualified licensing review. A private development repository does not waive those obligations when binaries are distributed. Obtain any required alternative license or replace incompatible components before a commercial App Store launch.

Primary references: [GPLv3 text](https://www.gnu.org/licenses/gpl-3.0.html), [Aidoku source and license](https://github.com/Aidoku/Aidoku).

## Content, sources and downloads

A reader, a source list, a search result, or an API response does not grant manga reproduction or download rights. First launch includes only Honbako’s original, bundled manga tutorial; it installs no external source list or third-party manga. Settings → Getting Started explains personal files, self-hosted libraries and explicit provider setup. Honbako does not direct users to another reader's community. Do not advertise access to unlicensed scans. Check each provider’s terms and obtain permission for its artwork, metadata use, chapter access, and offline copies where required. User-supplied URLs alone do not establish permission.

A source catalog can be maintained in a Honbako-owned repository or Gist and linked directly inside the app. The existing importer reads ordinary JSON from an HTTP(S) URL; a separate community site or Discord invitation is not required. A private repository needs a deliberately public catalog endpoint, without embedding GitHub credentials in the app. Source manifests and installable packages must both be available, with their own code-license notices preserved. Catalog hosting location does not change content permissions or Apple's downloadable-code/plugin review requirements (Guidelines 2.5.2 and 4.7).

## Apple review and payments

Apple expects authorization for third-party content and accurate app descriptions. Review Guidelines 5.2 address intellectual property; 4.7 may matter for downloadable executable source packages; 3.1.1 governs digital feature purchases. Document provider permissions and demonstrate a review account or personal-server fixture when needed. Use StoreKit for Pro, provide restore purchases, explain notification permission, and disclose network/background activity. Do not present a source picker as an App Review workaround. Regional rules and the final distribution model must be checked before submission.

Primary references: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [complete review information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/), [reader-app guidance](https://developer.apple.com/support/reader-apps/).

## Remaining external configuration

- Configure the Pro product in App Store Connect, including product type and pricing. If it is an auto-renewable subscription, add the required period, renewal, terms and privacy disclosures to its purchase presentation before enabling sales.
- Confirm signing capabilities and iCloud container provisioning for `com.missingems.honbaku`.
- Resolve distribution licensing and publisher/provider authorizations before submitting to Apple.

The app has no recommendation feed or scheduled metadata poll. The installer-only Pages workflow does not access a manga catalog or model API.

## Duo cover display

The optional Show Manga Cover feature uses Apple’s camera-capture scene accessory while a book is open on hinged hardware. It starts a video-only camera session to make the outer accessory available; no microphone, photo output, recording output or video-data sink is attached. Permission is requested explicitly, Settings explains the camera use, and hiding the cover, closing/folding the device or backgrounding stops capture. This behavior is disclosed in the review notes and must be evaluated in review; using the public accessory API does not establish review approval. [Apple’s multi-display explanation](https://developer.apple.com/videos/play/tech-talks/111464/).
