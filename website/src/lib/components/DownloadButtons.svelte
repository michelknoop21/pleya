<script lang="ts">
  import AppleIcon from "~icons/simple-icons/apple";
  import GooglePlayIcon from "~icons/simple-icons/googleplay";
  import LinuxIcon from "~icons/simple-icons/linux";
  import WindowsIcon from "./WindowsIcon.svelte";
  import { PUBLIC_TESTFLIGHT_URL, betaLinkReady } from "$lib/config";

  const comingSoon = [
    { label: "Android", icon: GooglePlayIcon },
    { label: "Windows", icon: WindowsIcon },
    { label: "Linux", icon: LinuxIcon },
  ];
</script>

<div class="download-buttons">
  <!-- Primary: TestFlight beta CTA for Apple platforms -->
  {#if betaLinkReady}
    <a
      href={PUBLIC_TESTFLIGHT_URL}
      target="_blank"
      rel="noopener noreferrer"
      class="beta-cta"
    >
      <AppleIcon />
      <span class="beta-cta-text">
        <span class="beta-cta-title">Join the beta</span>
        <span class="beta-cta-sub">iPhone · Apple TV · macOS</span>
      </span>
    </a>
  {:else}
    <button type="button" class="beta-cta" disabled aria-disabled="true">
      <AppleIcon />
      <span class="beta-cta-text">
        <span class="beta-cta-title">Join the beta — coming soon</span>
        <span class="beta-cta-sub">iPhone · Apple TV · macOS</span>
      </span>
    </button>
  {/if}

  <!-- Other platforms: not yet available -->
  <div class="soon-row">
    <span class="soon-label">More platforms coming</span>
    <div class="soon-chips">
      {#each comingSoon as platform}
        {@const Icon = platform.icon}
        <span class="soon-chip">
          <Icon />
          {platform.label}
        </span>
      {/each}
    </div>
  </div>
</div>

<style>
  .download-buttons {
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
  }

  .beta-cta {
    display: inline-flex;
    align-items: center;
    gap: 0.875rem;
    align-self: flex-start;
    min-height: 3.5rem;
    padding: 0.75rem 1.5rem;
    border-radius: 1rem;
    background: var(--gradient-brand);
    color: #fff;
    text-align: left;
    transition: filter 150ms ease, transform 150ms ease, box-shadow 150ms ease;
    box-shadow: 0 8px 30px -10px var(--color-accent-glow);
  }

  .beta-cta:hover:not(:disabled) {
    filter: brightness(1.08);
    transform: translateY(-2px);
    box-shadow: 0 14px 40px -12px var(--color-accent-glow);
  }

  .beta-cta:active:not(:disabled) {
    transform: translateY(0);
  }

  .beta-cta:disabled {
    cursor: default;
    filter: saturate(0.55) brightness(0.8);
    box-shadow: none;
  }

  .beta-cta :global(svg) {
    width: 1.5rem;
    height: 1.5rem;
    flex-shrink: 0;
  }

  .beta-cta-text {
    display: flex;
    flex-direction: column;
    line-height: 1.2;
  }

  .beta-cta-title {
    font-size: 1rem;
    font-weight: 700;
  }

  .beta-cta-sub {
    font-size: 0.75rem;
    font-weight: 500;
    opacity: 0.85;
    letter-spacing: 0.01em;
  }

  .soon-row {
    display: flex;
    flex-direction: column;
    gap: 0.625rem;
  }

  .soon-label {
    color: var(--color-text-faint);
    font-size: 0.75rem;
    font-weight: 600;
    letter-spacing: 0.06em;
    text-transform: uppercase;
  }

  .soon-chips {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }

  .soon-chip {
    display: inline-flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 0.875rem;
    border: 1px solid var(--color-border);
    border-radius: 9999px;
    color: var(--color-text-faint);
    font-size: 0.8125rem;
    font-weight: 500;
  }

  .soon-chip :global(svg) {
    width: 0.875rem;
    height: 0.875rem;
    opacity: 0.7;
  }
</style>
