<!--
  Het drie-puntenmenu op een kaart. Elke regel gebruikt een bestaand
  protocoleinde en bestaand scherm (DEC-046): kijkstatus en favoriet via
  personalApi, "Bekeken door" en de admin-schermen als link, informatie in de
  bestaande VersionPanel en ontkoppelen via de matchcall van het beheer. Het
  menu zelf is ActionMenu.
-->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { adminSettingsApi } from '../api/adminSettings';
  import { describeError } from '../api/errors';
  import { personalApi } from '../api/personal';
  import type { Item } from '../api/types';
  import { t } from '../i18n';
  import { addToList } from '../stores/addToList.svelte';
  import { session } from '../stores/session.svelte';
  import ActionMenu from './lists/ActionMenu.svelte';
  import ConfirmDialog from './ConfirmDialog.svelte';
  import VersionPanel from './VersionPanel.svelte';

  let { item }: { item: Item } = $props();

  // De kaart kent zijn item alleen uit de lijst; wat hier verandert houden we lokaal bij.
  let favorite = $state<boolean | undefined>();
  let watched = $state<boolean | undefined>();
  let full = $state<Item | null>(null);
  let infoOpen = $state(false);
  let unlinkOpen = $state(false);
  let busy = $state(false);
  let note = $state('');

  const caps = $derived(session.capabilities);
  const playable = $derived(item.kind === 'movie' || item.kind === 'episode');
  const isFavorite = $derived(favorite ?? !!item.favorite);
  const isWatched = $derived(watched ?? !!item.user_state?.watched);
  const admin = $derived(session.canAdminister && (item.kind === 'movie' || item.kind === 'show'));
  const query = $derived(`?item=${encodeURIComponent(item.id)}`);

  // Een mislukte actie meldt zich in dezelfde dialoog als de informatie.
  async function run(work: () => Promise<void>): Promise<void> {
    note = '';
    try {
      await work();
    } catch (err) {
      note = describeError(err);
      infoOpen = true;
    }
  }

  async function showInfo(): Promise<void> {
    infoOpen = true;
    note = '';
    if (full?.id === item.id) return;
    try {
      full = await session.client.item(item.id);
    } catch (err) {
      note = describeError(err);
    }
  }

  const actions = $derived.by(() => {
    const list: { label: string; danger?: boolean; onselect: () => void }[] = [];
    if (caps?.collections === true || caps?.playlists === true) {
      list.push({ label: t('lists.add.title'), onselect: () => addToList.open(item) });
    }
    if (caps?.watch_state && playable) {
      list.push({
        label: t(isWatched ? 'personal.markUnwatched' : 'personal.markWatched'),
        onselect: () => void run(async () => {
          const next = !isWatched;
          await personalApi(session.client).setWatched(item.id, next, item.duration_ms ?? undefined);
          watched = next;
        })
      });
    }
    if (caps?.favorites) {
      list.push({
        label: t(isFavorite ? 'personal.removeFavorite' : 'personal.addFavorite'),
        onselect: () => void run(async () => {
          const next = !isFavorite;
          await personalApi(session.client).setFavorite(item.id, next);
          favorite = next;
        })
      });
    }
    if (playable) list.push({ label: t('card.info'), onselect: () => void showInfo() });
    if (session.canAdminister && caps?.watch_state && item.kind !== 'season') {
      list.push({ label: t('watchedBy.title'), onselect: () => void goto(`/items/${encodeURIComponent(item.id)}#watched-by`) });
    }
    if (admin) {
      list.push({ label: t('admin.match.title'), onselect: () => void goto(`/admin/metadata/match${query}`) });
      list.push({ label: t('card.unlink'), danger: true, onselect: () => (unlinkOpen = true) });
      if (caps?.metadata_overrides === true || caps?.artwork_choices === true) {
        list.push({ label: t('admin.metadata.editor.title'), onselect: () => void goto(`/admin/metadata/edit${query}`) });
      }
    }
    return list;
  });

  async function unlink(): Promise<void> {
    busy = true;
    await run(() => adminSettingsApi(session.client).clearMetadataMatch(item.id).then(() => undefined));
    busy = false;
    unlinkOpen = false;
  }
</script>

{#if actions.length}
  <ActionMenu label={t('card.menu', { title: item.title })} {actions} size="plain" />
{/if}

<ConfirmDialog
  bind:open={infoOpen}
  title={item.title}
  message={note}
  confirmLabel={t('card.close')}
  danger={false}
  onconfirm={() => (infoOpen = false)}
>
  {#if !note}
    {#if full?.versions?.[0]}<VersionPanel version={full.versions[0]} />{:else}<p>{t('loading')}</p>{/if}
  {/if}
</ConfirmDialog>
<ConfirmDialog
  bind:open={unlinkOpen}
  {busy}
  title={t('card.unlink.title')}
  message={t('card.unlink.body', { title: item.title })}
  confirmLabel={t('card.unlink')}
  onconfirm={() => void unlink()}
/>
