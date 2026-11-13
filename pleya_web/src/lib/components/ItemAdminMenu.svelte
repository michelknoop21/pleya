<!--
  "Meer acties" op het filmdetail: de ingangen naar de bestaande beheerpagina's
  voor dit item. Alleen eigenaar en beheerder zien het menu; een lid heeft geen
  regels en dus geen knop. Elke regel volgt de capability van de pagina waar hij
  naartoe gaat, net als CardMenu.
-->
<script lang="ts">
  import { goto } from '$app/navigation';
  import type { Item } from '../api/types';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte.js';
  import ActionMenu from './lists/ActionMenu.svelte';

  let { item }: { item: Pick<Item, 'id'> } = $props();

  const actions = $derived.by(() => {
    if (!session.canAdminister) return [];
    const caps = session.capabilities;
    const query = `?item=${encodeURIComponent(item.id)}`;
    const list = [{ label: t('admin.match.title'), onselect: () => void goto(`/admin/metadata/match${query}`) }];
    if (caps?.metadata_overrides === true || caps?.artwork_choices === true) {
      list.push({ label: t('admin.metadata.editor.title'), onselect: () => void goto(`/admin/metadata/edit${query}`) });
    }
    if (caps?.artwork_choices === true) {
      list.push({ label: t('detail.chooseArtwork'), onselect: () => void goto(`/admin/metadata/edit${query}#artwork`) });
    }
    return list;
  });
</script>

{#if actions.length > 0}
  <ActionMenu label={t('detail.moreActions')} {actions} />
{/if}
