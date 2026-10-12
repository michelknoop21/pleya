<script lang="ts">
  import ArrowIcon from '~icons/material-symbols-light/arrow-outward-rounded';
  import { cta as site } from '$lib/config';
  /** The site's one call to action as a pill, with the arrow in its own circle. */
  let { href = site.href, label = site.label }: { href?: string; label?: string } = $props();
</script>

<a class="cta bp-cta" {href}>{label}<span class="knob" aria-hidden="true"><ArrowIcon /></span></a>
