// Public web-app constants of M6+ sign-in. They ship in the site's own scripts and can change with any
// deploy; every other auth file reads them from here.

/// Value of the `X-Customer-Name` header the web app sends on authenticated calls.
const m6plusCustomer = 'm6web';

/// Release the web app reports in `X-Client-Release`.
const m6plusClientRelease = '6.53.0';

/// Identity service (SAP Gigya) of the EU1 data centre, and the site's public API key for it.
const m6plusGigyaHost = 'accounts.eu1.gigya.com';
const m6plusGigyaApiKey = '3_hH5KBv25qZTd_sURpixbQW6a4OsiIzIEF2Ei_2H7TXTGLJb_1Hr4THKZianCQhWK';

/// Endpoint that turns a signed Gigya identity into the broadcaster's own token.
const m6plusGetJwtUrl = 'https://front-auth.6cloud.fr/v2/platforms/m6group_web/getJwt';

/// How long before the token's real expiry a session counts as expired, so it is renewed first.
const m6plusSessionMargin = Duration(minutes: 1);

const m6plusAuthUserAgent = 'Plezy-Replay (+https://github.com/silkyclouds/plezy)';
