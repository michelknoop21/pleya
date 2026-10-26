<!--
  `/admin`: vanaf 900 het overzicht (20), daaronder de mobiele index (33). Het
  overzicht heeft onder 900 een eigen adres, `/admin/overview`.
-->
<script lang="ts">
  import AdminIndex from '#lib/admin/AdminIndex.svelte';
  import AdminOverview from '#lib/admin/AdminOverview.svelte';
  import OverviewLoader from '#lib/admin/OverviewLoader.svelte';
  import { t } from '#lib/i18n/index.js';
  import { viewport } from '#lib/stores/viewport.svelte.js';
</script>

<svelte:head>
  <title>{t('admin.title')} · {t('app.name')}</title>
</svelte:head>

<OverviewLoader>
  {#snippet children(data)}
    {#if viewport.wide}
      <AdminOverview {data} />
    {:else}
      <AdminIndex {data} />
    {/if}
  {/snippet}
</OverviewLoader>
