<!--
  Serverbeheer, metadata en artwork (northstar 29). Alleen lezen: de server kent
  voor dit onderwerp geen instelling in `PATCH /settings`, dus er is geen
  Opslaan. Gebouwd uit de dekking per bibliotheek en de lijst titels die
  aandacht vragen. Het providerpaneel en het artworkpaneel van de northstar
  staan er niet in omdat het contract geen route heeft die ze voedt; de
  tekstkaart "Wat de server niet doet" is wel overgenomen.
-->
<script lang="ts">
  import { adminApi } from '../../api/admin';
  import { adminSettingsApi } from '../../api/adminSettings';
  import { describeError } from '../../api/errors';
  import Panel from '../../components/Panel.svelte';
  import SkeletonPage from '../../components/SkeletonPage.svelte';
  import StateView from '../../components/StateView.svelte';
  import { t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import AdminPageHead from '../AdminPageHead.svelte';
  import AdminColumns from './AdminColumns.svelte';
  import AttentionPanel from './AttentionPanel.svelte';
  import CoverageTable from './CoverageTable.svelte';
  import { loadMetadata, type MetadataData } from './metadata';

  let data = $state<MetadataData | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);

  $effect(() => {
    void attempt;
    const controller = new AbortController();
    loadMetadata(session.client, adminApi(session.client), adminSettingsApi(session.client), controller.signal)
      .then((result) => {
        data = result;
        failure = null;
      })
      .catch((err: unknown) => {
        if (!controller.signal.aborted) failure = describeError(err);
      });
    return () => controller.abort();
  });

  const threshold = $derived(data?.rows.find((r) => r.coverage)?.coverage?.threshold ?? null);
</script>

<AdminPageHead
  title={t('admin.nav.metadata')}
  crumbs={[{ label: t('admin.title'), href: '/admin' }, { label: t('admin.nav.metadata') }]}
>
  {#snippet actions()}
    <a class="btn btn--secondary btn--sm" href="/admin/metadata/match">{t('admin.match.open')}</a>
  {/snippet}
</AdminPageHead>

{#if data}
  <AdminColumns>
    {#snippet left()}
      <CoverageTable rows={data!.rows} {threshold} />
    {/snippet}
    {#snippet right()}
      <AttentionPanel list={data!.attention} />
      <Panel>
        {#snippet title()}{t('admin.meta.not.title')}{/snippet}
        <p class="body">{t('admin.meta.not.body')}</p>
      </Panel>
    {/snippet}
  </AdminColumns>
{:else if failure}
  <StateView kind="error" message={failure} onRetry={() => (attempt += 1)} />
{:else}
  <SkeletonPage variant="compact" />
{/if}

<style>
  .body {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
