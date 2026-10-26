<!--
  De tabel Tokens (34, links): naam, namens wie, bereik, laatst gebruikt,
  verloopt en Intrekken. Alleen levende tokens: de server laat ingetrokken en
  verlopen tokens uit de lijst, dus de grijze rij "ingetrokken" van de
  northstar bestaat hier niet. Onder 900 stapelt hij (DataTable `stack`).
-->
<script lang="ts">
  import DataTable, { type Column } from '../../components/DataTable.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { plural, t } from '../../i18n';
  import { formatRelative } from '../../util/format';
  import { expiresText, isBroadScope, ownerText, scopeLabel, type TokenRow } from './tokens';

  interface Props {
    rows: TokenRow[];
    /** Id's van tokens waarvoor nu een intrekking loopt. */
    revoking: Record<string, boolean>;
    onrevoke: (row: TokenRow) => void;
  }

  let { rows, revoking, onrevoke }: Props = $props();

  const columns: Column[] = [
    { key: 'name', label: t('admin.tok.col.name') },
    { key: 'owner', label: t('admin.tok.col.owner') },
    { key: 'scope', label: t('admin.tok.col.scope') },
    { key: 'seen', label: t('admin.tok.col.seen'), showLabel: true },
    { key: 'expires', label: t('admin.tok.col.expires'), showLabel: true },
    { key: 'actions', label: t('admin.tok.col.actions'), align: 'end', hideLabel: true }
  ];
</script>

<DataTable
  {columns}
  {rows}
  label={t('admin.tok.list.title')}
  rowKey={(row) => row.token.id}
  rowData={(row) => ({ 'data-token': row.token.id })}
  stack
>
  {#snippet title()}{t('admin.tok.list.title')}{/snippet}
  {#snippet actions()}
    <span class="count">{plural('admin.tok.list.count', rows.length)}</span>
  {/snippet}
  {#snippet empty()}{t('admin.tok.list.empty')}{/snippet}
  {#snippet cell(row, column)}
    {#if column.key === 'name'}
      <span class="name">{row.token.name}</span>
    {:else if column.key === 'owner'}
      {ownerText(row.owner)}
    {:else if column.key === 'scope'}
      <StatusPill
        size="sm"
        tone={isBroadScope(row.token.scope) ? 'warn' : 'idle'}
        label={scopeLabel(row.token.scope)}
      />
    {:else if column.key === 'seen'}
      {formatRelative(row.token.last_seen_at) ?? ''}
    {:else if column.key === 'expires'}
      {expiresText(row.token.expires_at)}
    {:else if column.key === 'actions'}
      <button
        type="button"
        class="btn btn--secondary btn--sm"
        disabled={revoking[row.token.id]}
        aria-label={t('admin.tok.revokeNamed', { name: row.token.name })}
        onclick={() => onrevoke(row)}
      >
        {t('admin.tok.revoke')}
      </button>
    {/if}
  {/snippet}
  {#snippet footer()}
    <p class="foot">{t('admin.tok.list.foot')}</p>
  {/snippet}
</DataTable>

<style>
  .name {
    font-weight: 600;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .count {
    font-size: 13px;
    color: var(--ink-3);
  }

  .foot {
    margin: 0;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
