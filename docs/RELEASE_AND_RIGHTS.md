# Release and content rights

Research date: 26 October 2026. These are engineering release constraints, not legal clearance or a guarantee of App Review approval.

## Reader engine

Honbako currently incorporates Aidoku’s GPLv3 reader. Charging for software is not itself forbidden by the GPL, but recipients must receive the license’s source and redistribution freedoms. Preserve the license, copyright notices, modification notices, and corresponding source. Apple distribution terms, DRM, third-party dependency licenses, and any proposed proprietary Pro components require a qualified licensing review. A private development repository does not waive those obligations when binaries are distributed. Obtain any required alternative license or replace incompatible components before a commercial App Store launch.

Primary references: [GPLv3 text](https://www.gnu.org/licenses/gpl-3.0.html), [Aidoku source and license](https://github.com/Aidoku/Aidoku).

## Content, sources and downloads

A reader, a community source list, a search result, or an API response does not grant manga reproduction or download rights. First launch installs no source list, manga, or chapter. The onboarding prioritizes personal files and self-hosted libraries, explains explicit provider setup, and links community documentation separately. Do not advertise access to unlicensed scans. Check each provider’s terms and obtain permission for its artwork, metadata use, chapter access, and offline copies where required. User-supplied URLs alone do not establish permission.

Recommendation data contains factual catalog fields, original short notes, and reviewed official publisher links, without chapter files or copied cover artwork. Open Library’s catalog licensing and API usage limits are documented separately in [RECOMMENDATIONS.md](RECOMMENDATIONS.md). Commercial scale requires a fresh provider-use review.

## Apple review and payments

Apple expects authorization for third-party content and accurate app descriptions. Review Guidelines 5.2 address intellectual property; 4.7 may matter for downloadable executable source packages; 3.1.1 governs digital feature purchases. Document provider permissions and demonstrate a review account or personal-server fixture when needed. Use StoreKit for Pro, provide restore purchases, explain notification permission, and disclose network/background activity. Do not present a source picker as an App Review workaround. Regional rules and the final distribution model must be checked before submission.

Primary references: [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/), [complete review information](https://developer.apple.com/help/app-review/before-submitting-for-review/complete-review/), [reader-app guidance](https://developer.apple.com/support/reader-apps/).

## Remaining external configuration

- Configure the Pro product in App Store Connect, including product type and pricing. If it is an auto-renewable subscription, add the required period, renewal, terms and privacy disclosures to its purchase presentation before enabling sales.
- Confirm signing capabilities and iCloud container provisioning for `com.missingems.honbaku`.
- Resolve GitHub's account payment/spending-limit restriction so the scheduled recommendation job and Pages deployment can start.
- Resolve distribution licensing and publisher/provider authorizations before submitting to Apple.

The optional Anthropic key is configured only as an Actions secret, with an explicitly selected Sonnet model. The maintainer supplied a public Open Library request contact and enabled the daily metadata poll. Neither credential is embedded in the app; scheduled runs make no paid model requests.

## Duo cover display

Apple’s documented outer-display scene accessory requires an active camera session. Honbako does not start a camera solely to display cover art and does not expose a nonfunctional cover-display switch. [Apple’s multi-display explanation](https://developer.apple.com/videos/play/tech-talks/111464/).
