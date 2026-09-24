// Single source of truth for Pleya's outbound links and beta state.
//
// Pleya is currently in a private TestFlight beta (iOS · Apple TV · macOS) and
// is not yet in any app store. Fill the values below when they exist.

/**
 * Public TestFlight invite link (e.g. https://testflight.apple.com/join/XXXXXXXX).
 * When empty, the CTA falls back to the "Join the waitlist" mailto: link below.
 */
export const PUBLIC_TESTFLIGHT_URL = '';

/** Inbox for the "Join the waitlist" mailto: link. */
export const WAITLIST_FALLBACK_EMAIL = 'info@michelknoop.nl';

/** Upstream open-source project Pleya is based on (GPL-3.0 attribution). */
export const UPSTREAM_REPO_URL = 'https://github.com/edde746/plezy';

/**
 * Public repository with Pleya's own (modified) source code. GPL-3.0 §6
 * requires the corresponding source of THIS fork to be available; linking
 * only upstream is not sufficient once builds are distributed. Fill this with
 * the public fork URL; until then the footer points at the shipped NOTICE.
 */
export const FORK_SOURCE_URL = 'https://github.com/michelknoop21/pleya';

/** Effective "Source" link target: the public fork when available. */
export const SOURCE_REPO_URL = FORK_SOURCE_URL.trim().length > 0 ? FORK_SOURCE_URL : '/NOTICE.txt';

/** Whether a real TestFlight link is available yet. */
export const betaLinkReady = PUBLIC_TESTFLIGHT_URL.trim().length > 0;

// Until a public TestFlight link exists the one action is the waitlist, a
// pre-filled mail (there is no webhook). Filling PUBLIC_TESTFLIGHT_URL above
// switches every CTA on the site to the beta.
export const cta = betaLinkReady
  ? { href: PUBLIC_TESTFLIGHT_URL, label: 'Join the TestFlight beta', note: 'Opens TestFlight for iPhone, Apple TV and Mac.' }
  : {
      href: `mailto:${WAITLIST_FALLBACK_EMAIL}?subject=${encodeURIComponent('Pleya waitlist')}&body=${encodeURIComponent('Please add me to the Pleya waitlist.')}`,
      label: 'Join the waitlist',
      note: 'Private TestFlight beta. The button opens your mail app with a pre-filled request.',
    };
export type Cta = typeof cta;
