# Privacy and release data-flow review

## Current build69 release status — 30 October 2026

Production managed MCP is deployed with strict Production purchase verification; the isolated Sandbox service remains separate. Verified StoreKit transaction environments select the matching service automatically. Production Apple API access still returns401 before the first App Store release, while Sandbox200 succeeds. No fallback between purchase environments was added.

The published privacy policy now describes shared library/source/search and all-reading-history requests, persistent current-page/annotation content, bounded jobs, connected-disconnect deletion, indefinite minimal hashed ownership records, and a private contact. App Store Connect now declares eight retained-data types for App Functionality, linked to the installation/workspace, with tracking set to No. See build69/privacy-draft.json and the published UI proof for the exact categories. The older audit/checkpoints below describe earlier builds and are retained as history.

Engineering audit: updated 28 October 2026. This is preparation for the owner's declarations, not a published privacy policy or a legal attestation.

| Flow | Evidence in this checkout | Submission implication |
| --- | --- | --- |
| Library, chapters, bookmarks, reading history | Core Data in the app container; `CoreDataManager.createContainer` | User content and reading activity exist on device. Review retention and deletion before answering labels. |
| Optional progress sync | `NSPersistentCloudKitContainer`, private database scope | Library metadata and reading records may leave the device through the user's private iCloud database. Cloud model also includes related session/local-file metadata. Files themselves are not app progress-sync payloads. |
| Device provenance | `SumiReadingProvenance` stores identifierForVendor, or a generated UUID, and device name in reading records | Do not claim the app never uses identifiers. These identify which device saved a reading position; no advertising identifier was found. |
| User-selected sources and servers | Source manager, HTTP(S) source lists, native connector, imported source runners | Queries, identifiers, credentials when configured, image requests and network information reach providers. Their retention/collection policies are not established by this source audit. |
| Pro | StoreKit verified transactions; cached product/expiry/revocation/verification dates | Apple processes payment. No developer payment server or raw card handling was found. Real monthly product configuration remains unverified. |
| Alerts | `NotificationManager`, background library refresh, local notification requests | Permission and background refresh are required. This is not a developer-operated real-time push feed. |
| Optional outer cover display | `HonbakoCoverDisplaySession`, video-only camera input and a camera-capture scene accessory | Explicit camera permission; no microphone, recordings, photo output, video-data output or developer transmission of camera frames. Capture stops when the feature is hidden, the book closes, the hinge closes or the app backgrounds. Disclose this optional camera use in review. |
| Diagnostics | Local logger and opt-in DEBUG-only gesture/performance probes | No advertising/analytics SDK or developer analytics endpoint found in app source. TestFlight separately supplies Apple's testing diagnostics under its own settings. Review the final SDK privacy report. |

`Aidoku/App/Resources/PrivacyInfo.xcprivacy` describes the app-owned required-reason APIs found in the audit: UserDefaults `CA92.1`; file metadata in the app/CloudKit containers `C617.1`; metadata for user-granted files `3B52.1`. Apple's current definitions were checked in [required-reason API documentation](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api). The system-uptime performance probe is DEBUG-only. The ZIPFoundation checkout has its own manifest. Root must confirm manifests are actually present in the final archive and review all integrated SDKs; the app manifest does not replace SDK obligations.

The manifest sets tracking to false based on the audited implementation. It deliberately does not submit collected-data categories. The owner must determine the App Store Connect answers for app functionality, user content/reading activity, device provenance, purchases, diagnostics, and user-chosen providers using their actual access and retention practices. A blanket “Data Not Collected” answer has not been made. Apple's collection definition and third-party-partner requirements are in [App privacy details](https://developer.apple.com/app-store/app-privacy-details/) and [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/).

The in-app Privacy Information sheet describes these current flows. `web-drafts` contains localized support drafts with the authorized feedback email, plus policy drafts whose operator identity, privacy contact, retention details, and public policy URL still require owner review. These drafts have not been approved or published as policy. A real policy URL is still required in App Store Connect and must be linked in the final subscription presentation.

The existing `ITSAppUsesNonExemptEncryption=NO` build setting is not a new export determination. Apple documents an exemption path for encryption limited to Apple operating-system facilities, but the owner must review the final engine/dependency/source behavior and markets before confirming the answer. See [Apple export-compliance table](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/).


## Remote MCP release preparation — 30 October 2026

The new optional hosted service retains shared library/reading metadata, the latest shared page’s identifiers and annotations, that page’s image only after an AI asked for it, queued work, installation credentials/hashes, and purchase identifiers for subscription checks. The earlier “Data Not Collected” answer must be reassessed and updated before a public build enables hosted enrollment. The policy source and in-app privacy information now describe this flow, provider processing and disconnect deletion. These edits have not been published and the live App Store privacy answer has not been changed.

The per-user remote route remains disabled pending App Store Server API credentials, verification with a real purchase, provider OAuth acceptance and deployment review. Existing local and private pilot connections are preserved. No billing plan or subscription price changed.
