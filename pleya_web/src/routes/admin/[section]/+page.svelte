<!--
  Een beheersectie zonder eigen scherm. `overview` is het overzicht (20) op
  een eigen adres, voor de mobiele index; de rest zegt dat hij in een volgend
  deel komt, zodat geen link in de zijbalk dood is.
-->
<script lang="ts">
  import AdminOverview from '#lib/admin/AdminOverview.svelte';
  import OverviewLoader from '#lib/admin/OverviewLoader.svelte';
  import { ADMIN_ROOT, sectionById } from '#lib/admin/sections.js';
  import StateView from '#lib/components/StateView.svelte';
  import { t } from '#lib/i18n/index.js';

  let { data }: { data: { section: string } } = $props();

  const section = $derived(sectionById(data.section));
</script>

<svelte:head>
  <title>{section ? t(section.label) : t('admin.title')} · {t('app.name')}</title>
</svelte:head>

{#if section?.id === 'overview'}
  <OverviewLoader>
    {#snippet children(overview)}
      <AdminOverview data={overview} />
    {/snippet}
  </OverviewLoader>
{:else if section}
  <h1 class="title">{t(section.label)}</h1>
  <StateView title={t('admin.later.title')} message={t('admin.later.body')}>
    {#snippet actions()}
      <a class="btn btn--secondary btn--sm" href={ADMIN_ROOT}>{t('admin.later.action')}</a>
    {/snippet}
  </StateView>
{/if}

<style>
  .title {
    margin: 0 0 8px;
    font-size: 34px;
    font-weight: 700;
    line-height: 1.1;
    letter-spacing: -0.01em;
  }

  @media (max-width: 899px) {
    .title {
      font-size: 26px;
    }
  }
</style>
