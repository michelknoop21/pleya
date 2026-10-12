<script lang="ts">
  import ArrowIcon from '~icons/material-symbols-light/arrow-outward-rounded';
  import { cta as site } from '$lib/config';
  import CtaNote from './CtaNote.svelte';
  /** The site's one call to action as a pill, with the arrow in its own circle. `note` adds the explanation under it. */
  let { href = site.href, label = site.label, note = false }: { href?: string; label?: string; note?: boolean } = $props();
</script>

<a class="cta bp-cta" {href}>{label}<span class="knob" aria-hidden="true"><ArrowIcon /></span></a>
{#if note}<CtaNote />{/if}
