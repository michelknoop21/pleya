# Pleya Website

Source for [pleya.app](https://pleya.app), built with SvelteKit and exported as a static site.

Pleya is a beautiful client for Plex and Jellyfin, currently in TestFlight beta for iOS, tvOS, and macOS. It is a fork based on the open-source [Plezy](https://github.com/edde746/plezy) project (GPL-3.0).

## Development

```bash
bun install
bun run dev
```

## Configuration

Outbound links and beta state live in `src/lib/config.ts`:

- `PUBLIC_TESTFLIGHT_URL` — public TestFlight invite link. When empty, the "Join the beta" CTA renders a disabled "coming soon" state.
- `WAITLIST_WEBHOOK_URL` — webhook that receives waitlist sign-ups (`POST` with `{ email }`). When empty, the form falls back to a `mailto:` link.
- `SOURCE_REPO_URL` — upstream project for the GPL-3.0 attribution in the footer.

## Checks

```bash
bun run check
```

## Build

```bash
bun run build
```

The production output is written to `build/` and is intentionally ignored by git.
