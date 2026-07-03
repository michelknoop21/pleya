// Single source of truth for Pleya's outbound links and beta state.
//
// Pleya is currently in a private TestFlight beta (iOS · Apple TV · macOS) and
// is not yet in any app store. Fill the values below when they exist.

/**
 * Public TestFlight invite link (e.g. https://testflight.apple.com/join/XXXXXXXX).
 * When empty, the "Join the beta" CTA renders as a disabled "coming soon" state.
 */
export const PUBLIC_TESTFLIGHT_URL = '';

/**
 * Webhook that receives waitlist sign-ups (a POST with { email } JSON body).
 * When empty, the waitlist form falls back to a pre-filled mailto: link.
 */
export const WAITLIST_WEBHOOK_URL = '';

/** Fallback inbox used when no waitlist webhook is configured. */
export const WAITLIST_FALLBACK_EMAIL = 'info@michelknoop.nl';

/** Upstream open-source project Pleya is based on (GPL-3.0 attribution). */
export const SOURCE_REPO_URL = 'https://github.com/edde746/plezy';

/** Whether a real TestFlight link is available yet. */
export const betaLinkReady = PUBLIC_TESTFLIGHT_URL.trim().length > 0;
