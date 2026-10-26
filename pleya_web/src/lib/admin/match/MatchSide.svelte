<!--
  De rechterkolom van scherm 36: hoeveel titels er per uitkomst wachten en wat
  de server hier wel en niet draagt. Het veldenpaneel (overrides met herkomst)
  en de providerronde van de northstar staan er niet, want het contract kent
  geen route die ze voedt.
-->
<script lang="ts">
  import type { MetadataAttentionList } from '../../api/types';
  import Panel from '../../components/Panel.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { t } from '../../i18n';
  import { attentionStateLabel } from '../settings/metadata';
  import { countByState } from './match';

  let { list }: { list: MetadataAttentionList } = $props();

  const counts = $derived(countByState(list));
</script>

{#if counts.length > 0}
  <Panel>
    {#snippet title()}{t('admin.match.side.counts')}{/snippet}
    <ul class="counts">
      {#each counts as row (row.state)}
        <li>
          <StatusPill
            size="sm"
            tone={row.state === 'failed' ? 'err' : row.state === 'rejected' ? 'idle' : 'warn'}
            label={attentionStateLabel(row.state)}
          />
          <span class="n">{row.count}</span>
        </li>
      {/each}
    </ul>
  </Panel>
{/if}
<Panel>
  {#snippet title()}{t('admin.match.side.title')}{/snippet}
  <p class="body">{t('admin.match.side.body')}</p>
</Panel>

<style>
  .counts {
    display: grid;
    gap: 10px;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  li {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .n {
    font-variant-numeric: tabular-nums;
    color: var(--ink);
  }

  .body {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
