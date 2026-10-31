# Honbako branded MCP domains — live and verified

Both branded hosts passed strict public HTTPS, capabilities, issuer/resource discovery,
unauthenticated MCP challenge, and cross-origin rejection checks on 2026-10-30.
All 20 checks across the two branded and two legacy origins passed; evidence is in
`AppStore/review/build73/mcp-domain-live-checks.json`. Existing workers.dev clients retain
their original endpoints. Build 73 uses branded defaults for new connections while
preserving saved phone pairings and issuer-bound existing AI connections.

## Frozen mapping

| Environment | Existing Worker / storage owner | Legacy PUBLIC_ORIGIN (unchanged) | Exact REMOTE_ORIGIN_ALIASES entry | New MCP URL |
| --- | --- | --- | --- | --- |
| Production | `honbako-mcp` | `https://honbako-mcp.jun-19c.workers.dev` | `https://mcp.honbako.xyz` | `https://mcp.honbako.xyz/remote/mcp` |
| Apple Sandbox / TestFlight | `honbako-mcp-pro-preview` | `https://honbako-mcp-pro-preview.jun-19c.workers.dev` | `https://test-mcp.honbako.xyz` | `https://test-mcp.honbako.xyz/remote/mcp` |

Both Wrangler files retain workers.dev access. The exact custom-domain `routes` are
deployed: `mcp.honbako.xyz` on production and `test-mcp.honbako.xyz` on Sandbox,
each with `custom_domain: true`. Do not rename the Workers, change Durable Object classes, migrations,
bindings, object IDs, subscription environments or routing secrets. The authorization
object remains `oauth-v1`; workspace IDs remain the private installation UUID.
The legacy single-owner pilot is deliberately not exposed at the new production host.

## Deployment checkpoint

- Production version: `b24febbf-4635-4889-a2ac-1acc0f847a6d`.
- Sandbox version: `3c5c13c0-11fc-4cc6-bc65-3485aca5fd2b`.
- The account API confirms both custom-domain mappings in zone
  `709120a41d6a842b35327b8335c60dcc` (`honbako.xyz`, active Free Website).
- Cloudflare authoritative nameservers are `chad.ns.cloudflare.com` and
  `kayleigh.ns.cloudflare.com`; both MCP hosts resolve there to `104.21.17.27` and
  `172.67.219.198`.
- Registry RDAP confirms registration at `2026-10-30T13:57:16Z`, expiry on
  `2027-10-30T23:59:59Z`, the correct Cloudflare nameservers, and no client/server hold
  status. The transfer locks and initial add period do not indicate a DNS hold.
- By `2026-10-30T15:23:44Z`, both branded hosts resolved publicly and passed strict
  certificate-verified HTTPS checks without custom resolver overrides or disabled validation.
  The earlier registry-delegation and certificate-validation delay has cleared.
- Public discovery and rejection checks passed at all four origins. Authenticated migration
  scenarios passed in local workerd integration tests; a fresh owner-approved live branded
  OAuth connection remains a separate device check.

## Compatibility and security

- Exact trusted HTTPS origins only. There is no wildcard, forwarded-host trust,
  cross-environment fallback, URL redirect or generic proxy that rewrites OAuth audiences.
- Each request derives its base locally. The broker and workspace never mutate their
  shared default base during awaited operations.
- Discovery, authorization pages, enrollment responses and 401 resource metadata use
  the requested origin. An old client continues to receive old URLs; new clients use new URLs.
- OAuth registration, pending consent, authorization code and AI grants carry their
  issuer. Exact callback, S256 PKCE, browser cookie, resource, client authentication,
  Pro verification, grant lifetime and refresh rotation checks remain enforced.
- Records without an issuer are existing records and resolve only to the legacy
  PUBLIC_ORIGIN. Existing tokens, clients and in-flight authorization flows keep working
  there; a legacy code or refresh token cannot be exchanged at the branded issuer.
- Device credentials work at either trusted origin within the same environment. The
  paired phone may approve a branded AI request through its original endpoint. Enrollment
  on the new origin returns that same origin without allocating a new installation.
- AI access tokens remain issuer-bound even though they are opaque HMAC credentials.
  A connection created at one issuer must use that issuer for MCP and refresh/revoke.
- Do not change PUBLIC_ORIGIN as a cosmetic cleanup: it is the fallback issuer for
  pre-migration records. The app can prefer the new alias independently. Removing a
  legacy issuer needs a separate explicit retirement/data migration plan.

## Rollout after owner approval and completed registration

1. Confirm the domain is owned, its nameservers are active, and exact DNS/custom-domain
   hosts are unused. Keep Workers Free and decline unrelated upgrades or add-ons.
2. Review and deploy the alias-aware code and prepared custom-domain routes to the two
   existing Workers with their current bindings and secrets. Deployment attaches each
   exact custom domain to its matching Worker with managed TLS. Leave existing clients
   and phone pairings untouched; never point testing at production or vice versa.
3. Confirm both domain attachments and TLS are active. Registration has now been
   confirmed in the owner's account: zone `honbako.xyz`,
   `709120a41d6a842b35327b8335c60dcc`, active Free Website. The parent task also verified
   Workers Free in billing. These confirmations authorize no additional paid service.
4. Verify TLS, capabilities, issuer/resource metadata and unauthenticated MCP challenges
   at both old and new hosts. Confirm unknown hosts and cross-origin requests fail closed.
5. Verify an existing old-host connection still reads the same phone/library. Start a
   separate new-host OAuth flow, approve on the paired phone, then verify library access,
   source-management approval, refresh/revocation and issuer isolation. Do not log secrets.
6. Only after the server/domain checks pass, update the app's managed endpoint aliases:
   Production aliases share the existing production Keychain identity; Sandbox aliases
   share `remote-installation.sandbox`. Preserve the endpoint saved in every existing
   pairing. The new-AI setup display may show the preferred branded alias with explicit new-authorization guidance; do not alter the saved phone endpoint or an existing AI issuer.
7. Existing AI connections stay on their old URLs. A user choosing the branded issuer
   establishes a new OAuth connection; do not copy/print credentials or silently replace it.

Rollback: revert the app's default for new connections if needed and remove only new
host bindings/aliases after accounting for any new-host connections. Keep old hosts,
Workers, namespaces and secrets intact. An immediate rollback to code without issuer
checks is unsafe once branded grants exist; retain alias-aware code while retiring them.

## Local validation

`node --test cloudflare/test/remote-origins.test.js` covers missing-issuer legacy
clients/challenges/codes/grants, branded consent and refresh, preserved phone identity and
snapshot, unknown origin rejection, audience isolation, concurrent request bases and the
frozen deployment mapping.

`cloudflare/integration-remote-workerd.js` runs the actual Worker entrypoints, SQLite
Durable Objects and RPC locally. It exercises old and new discovery and consent, old-phone
approval of branded requests, same-library enrollment, tokens bound to their issuer,
unknown/CORS hosts, runtime restart persistence and disconnect revocation. All Apple
credentials and subscription responses in that test are fixtures. Its temporary bundle
and durable storage directory are removed in `finally`; it never deploys.
