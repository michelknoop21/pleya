<!--
  De beheerschil rond elke `/admin`-route.

  De load (`+layout.ts`) geeft een lid al een 404 voordat dit rendert. Dit
  blok is de tweede helft: kwam de rol pas later vast te staan (de server was
  onbereikbaar toen de load draaide), dan rendert er niets van beheer en draait
  de load opnieuw, die dan de 404 geeft. Zo doet de beheerlaag voor een lid
  nooit een aanvraag (S10.7).
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import { page } from '$app/state';
  import { invalidateAll } from '$app/navigation';

  import AdminLayout from '#lib/components/AdminLayout.svelte';
  import { activeSectionId } from '#lib/admin/sections.js';
  import { session } from '#lib/stores/session.svelte.js';

  let { children }: { children: Snippet } = $props();

  $effect(() => {
    if (session.phase === 'ready' && !session.canAdminister) void invalidateAll();
  });
</script>

{#if session.canAdminister}
  <AdminLayout active={activeSectionId(page.url.pathname)}>
    {@render children()}
  </AdminLayout>
{/if}
