<!--
  Titels die aandacht vragen (29, rechts): wat de server niet zelf aan een
  providermatch kon koppelen of waar het ophalen faalde
  (`GET /metadata/attention`). Alleen lezen; een match bevestigen of afwijzen
  hoort bij een eigen scherm (36) en staat hier niet. Vervangt het
  providerpaneel van de northstar, want het contract meldt niet of er een
  provider is ingesteld.
-->
<script lang="ts">
  import type { MetadataAttentionList } from '../../api/types';
  import Panel from '../../components/Panel.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { plural, t } from '../../i18n';
  import { attentionStateLabel } from './metadata';

  let { list }: { list: MetadataAttentionList | null } = $props();

  const SHOWN = 5;
</script>

<Panel>
  {#snippet title()}{t('admin.meta.attention.title')}{/snippet}
  {#snippet actions()}
    {#if list}
      <StatusPill
        size="sm"
        tone={list.total === 0 ? 'ok' : 'warn'}
        label={list.total === 0 ? t('admin.meta.attention.clear') : plural('admin.meta.attention.total', list.total)}
      />
    {/if}
  {/snippet}
  {#if list === null}
    <p class="body">{t('admin.meta.attention.unreadable')}</p>
  {:else if list.items.length === 0}
    <p class="body">{t('admin.meta.attention.none')}</p>
  {:else}
    <ul class="list">
      {#each list.items.slice(0, SHOWN) as item (item.item_id)}
        <li class="row" data-item={item.item_id}>
          <a class="name" href="/admin/metadata/match?item={encodeURIComponent(item.item_id)}"
            >{item.title}{item.year ? ` (${item.year})` : ''}</a
          >
          <span class="state">{attentionStateLabel(item.state)}</span>
        </li>
      {/each}
    </ul>
    {#if list.total > Math.min(list.items.length, SHOWN)}
      <p class="body more">
        {t('admin.meta.attention.more', { count: list.total - Math.min(list.items.length, SHOWN) })}
      </p>
    {/if}
  {/if}
</Panel>

<style>
  .body {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }

  .more {
    margin-top: 8px;
  }

  .list {
    display: grid;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .row {
    display: flex;
    justify-content: space-between;
    gap: 12px;
    padding: 9px 0;
    border-bottom: 1px solid var(--hairline);
    font-size: 14px;
  }

  .row:last-child {
    border-bottom: 0;
  }

  .name {
    min-width: 0;
    color: var(--ink);
    overflow-wrap: anywhere;
    text-decoration: underline;
    text-decoration-color: var(--hairline);
    text-underline-offset: 4px;
  }

  .name:hover {
    text-decoration-color: currentColor;
  }

  .state {
    flex: none;
    color: var(--ink-3);
    font-size: 12.5px;
  }
</style>
