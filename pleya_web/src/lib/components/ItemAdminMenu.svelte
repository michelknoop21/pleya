<!--
  "Meer acties" op het detail van een film, seizoen of aflevering: de ingangen
  naar de bestaande beheerpagina's (alleen bij een film) en het verwijderen
  van de titel met zijn bestanden. Alleen eigenaar en beheerder zien het menu;
  een lid heeft geen regels en dus geen knop. Elke regel volgt de capability
  van de pagina of het eindpunt erachter, net als CardMenu.
-->
<script lang="ts">
  import { goto } from '$app/navigation';
  import type { Item } from '../api/types';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte.js';
  import ItemDelete from './ItemDelete.svelte';
  import ActionMenu from './lists/ActionMenu.svelte';
  import { canRefreshMetadata, refreshMetadata } from './refreshMetadata';

  let { item, onreload }: { item: Pick<Item, 'id' | 'title' | 'kind' | 'parent_id'>; onreload?: () => void } = $props();

  let deleteOpen = $state(false);
  const canDelete = $derived(session.canAdminister && session.capabilities?.media_delete === true);
  let message = $state('');

  const actions = $derived.by(() => {
    if (!session.canAdminister) return [];
    const caps = session.capabilities;
    const query = `?item=${encodeURIComponent(item.id)}`;
    const list: { label: string; danger?: boolean; onselect: () => void }[] = [];
    if (item.kind === 'movie') {
      list.push({ label: t('admin.match.title'), onselect: () => void goto(`/admin/metadata/match${query}`) });
      if (caps?.metadata_overrides === true || caps?.artwork_choices === true) {
        list.push({ label: t('admin.metadata.editor.title'), onselect: () => void goto(`/admin/metadata/edit${query}`) });
      }
      if (caps?.artwork_choices === true) {
        list.push({ label: t('detail.chooseArtwork'), onselect: () => void goto(`/admin/metadata/edit${query}#artwork`) });
      }
    }
    if (canRefreshMetadata()) {
      list.push({ label: t('detail.refreshMetadata'), onselect: () => void refreshMetadata(item.id).then(text => (message = text)) });
    }
    if (canDelete) list.push({ label: t('item.delete.action'), danger: true, onselect: () => (deleteOpen = true) });
    return list;
  });
</script>

{#if actions.length > 0}
  <ActionMenu label={t('detail.moreActions')} {actions} />
{/if}
{#if canDelete}
  <ItemDelete {item} bind:open={deleteOpen} {onreload} />
{/if}

{#if message}<p class="refresh-note" role="status">{message}</p>{/if}

<style>
  .refresh-note {
    margin: 0;
    font-size: 13px;
    color: var(--ink-3);
  }
</style>
