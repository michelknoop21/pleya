<script lang="ts">
  import ArrowIcon from '~icons/material-symbols-light/arrow-outward-rounded';
  import { betaLinkReady, cta as site, WAITLIST_FALLBACK_EMAIL } from '$lib/config';
  /** The site's one call to action as a pill, with the arrow in its own circle. `note` adds the explanation under it. */
  let { href = site.href, label = site.label, note = false }: { href?: string; label?: string; note?: boolean } = $props();
</script>

<a class="cta bp-cta" {href}>{label}<span class="knob" aria-hidden="true"><ArrowIcon /></span></a>
{#if note}
  <p class="cta-note">
    {site.note}
    {#if !betaLinkReady}No mail app on this device? Write to <span class="mail">{WAITLIST_FALLBACK_EMAIL}</span>.{/if}
  </p>
{/if}

<style>
  .mail { color: var(--ink); user-select: all; }
</style>
