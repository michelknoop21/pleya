<script lang="ts">
  import Logo from "$lib/components/Logo.svelte";
  import AppleIcon from "~icons/simple-icons/apple";
  import { PUBLIC_TESTFLIGHT_URL, betaLinkReady } from "$lib/config";
</script>

<svelte:head>
  <title>Open in Pleya</title>
  <meta name="description" content="Open this QR code with the Pleya app." />
  <meta name="robots" content="noindex, nofollow" />
  <link rel="canonical" href="https://pleya.app/scan" />

  <meta property="og:type" content="website" />
  <meta property="og:site_name" content="Pleya" />
  <meta property="og:title" content="Open in Pleya" />
  <meta property="og:description" content="Open this QR code with the Pleya app." />
  <meta property="og:url" content="https://pleya.app/scan" />
  <meta property="og:image" content="https://pleya.app/og/pleya-social.png" />

  <meta name="twitter:card" content="summary_large_image" />
  <meta name="twitter:title" content="Open in Pleya" />
  <meta name="twitter:description" content="Open this QR code with the Pleya app." />
  <meta name="twitter:image" content="https://pleya.app/og/pleya-social.png" />
</svelte:head>

<div class="scan-page">
  <div class="scan-card">
    <span class="scan-logo"><Logo alt="Pleya" /></span>

    <h1 class="scan-heading">Scan in Pleya</h1>
    <p class="scan-description">To use this feature, open this QR code with the Pleya app.</p>

    {#if betaLinkReady}
      <a
        href={PUBLIC_TESTFLIGHT_URL}
        target="_blank"
        rel="noopener noreferrer"
        class="beta-button"
      >
        <AppleIcon />
        Join the beta
      </a>
    {:else}
      <p class="beta-note">
        <AppleIcon />
        Pleya is in private TestFlight beta for iPhone, Apple TV &amp; macOS.
      </p>
    {/if}
  </div>
</div>

<style>
  .scan-page {
    display: flex;
    min-height: 100vh;
    align-items: center;
    justify-content: center;
    padding: 4rem 1.5rem;
  }

  .scan-card {
    display: flex;
    max-width: 24rem;
    flex-direction: column;
    align-items: center;
    text-align: center;
  }

  .scan-logo {
    margin-bottom: 1.5rem;
  }

  .scan-logo :global(img) {
    width: 4rem;
    height: 4rem;
  }

  .scan-heading {
    margin-bottom: 0.5rem;
    font-size: 1.5rem;
    font-weight: 700;
    line-height: 2rem;
  }

  .scan-description {
    margin-bottom: 2rem;
    color: var(--color-text-muted);
  }

  .beta-button {
    display: inline-flex;
    align-items: center;
    gap: 0.625rem;
    padding: 0.75rem 1.5rem;
    border-radius: 9999px;
    background: var(--gradient-brand);
    color: #fff;
    font-size: 0.9375rem;
    font-weight: 600;
    line-height: 1.25rem;
    transition: filter 150ms ease;
  }

  .beta-button:hover {
    filter: brightness(1.08);
  }

  .beta-button :global(svg) {
    width: 1.125rem;
    height: 1.125rem;
  }

  .beta-note {
    display: inline-flex;
    align-items: center;
    gap: 0.625rem;
    padding: 0.75rem 1.25rem;
    border: 1px solid var(--color-border);
    border-radius: 1rem;
    color: var(--color-text-muted);
    font-size: 0.875rem;
    line-height: 1.4;
    text-align: left;
  }

  .beta-note :global(svg) {
    width: 1.125rem;
    height: 1.125rem;
    flex-shrink: 0;
    color: var(--color-accent-2);
  }
</style>
