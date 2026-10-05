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

- `PUBLIC_TESTFLIGHT_URL`: public TestFlight invite link. When empty, the "Join the beta" CTA renders a disabled "coming soon" state.
- `SOURCE_REPO_URL`: upstream project for the GPL-3.0 attribution in the footer.

## Checks

```bash
bun run check
```

## Build

```bash
bun run build
```

The production output is written to `build/` and is intentionally ignored by git.

## TV download and counter

`/install` is an unlisted page for the Android TV APK. The APK itself is mounted from
`/volume1/docker/pleya/downloads` on the NAS, outside the site image. The download
button first calls `/get/android-tv`, which records one download start and redirects
to the APK. `/download-counts.json` returns the total shown on the page. These are
download starts, not completed transfers or installations.

The counter database lives in `/volume1/docker/pleya/download-data` and survives
website redeploys. It stores daily totals only; no visitor identifiers. Deploy with
`./deploy-nas.sh`, which creates that data directory and starts both containers.
