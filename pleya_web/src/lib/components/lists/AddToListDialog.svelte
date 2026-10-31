<!--
  "Toevoegen aan" (S19): één dialoog in de schil, geopend vanaf elke kaart en
  detailpagina. Kies een of meer eigen lijsten, of geef een nieuwe een naam.
  `POST .../items` zet achteraan en herhalen is onschadelijk, dus een titel die
  er al in staat is geen fout.

  Een afspeellijst bevat alleen wat zelf afspeelt. Bij een serie of seizoen staat
  die groep er niet en legt een regel uit waarom.
-->
<script lang="ts">
  import { untrack } from 'svelte';
  import ConfirmDialog from '../ConfirmDialog.svelte';
  import Field from '../Field.svelte';
  import Select from '../Select.svelte';
  import type { Collection, Playlist } from '../../api/types';
  import { describeError } from '../../api/errors';
  import { allPages, listsApi, type ListKind } from '../../api/lists';
  import { addToList } from '../../stores/addToList.svelte';
  import { session } from '../../stores/session.svelte';
  import { t } from '../../i18n';

  const item = $derived(addToList.item);
  let open = $state(false);
  let collections = $state<Collection[]>([]);
  let playlists = $state<Playlist[]>([]);
  let chosen = $state<Record<string, boolean>>({});
  let newName = $state('');
  let newKind = $state<string>('collection');
  let loading = $state(false);
  let busy = $state(false);
  let error = $state<string | null>(null);
  // Blijft staan als het item niet toegevoegd kon worden: een tweede klik maakt
  // dan geen tweede lijst met dezelfde naam.
  let created: { name: string; kind: ListKind; id: string; title: string } | null = null;

  const canCollect = $derived(session.capabilities?.collections === true);
  const canPlaylist = $derived(session.capabilities?.playlists === true);
  const playable = $derived(item?.kind === 'movie' || item?.kind === 'episode');
  const offerPlaylists = $derived(canPlaylist && playable);
  const kinds = $derived([
    ...(canCollect ? [{ value: 'collection', label: t('lists.add.newCollection') }] : []),
    ...(offerPlaylists ? [{ value: 'playlist', label: t('lists.add.newPlaylist') }] : [])
  ]);
  const anyChosen = $derived(Object.values(chosen).some(Boolean) || newName.trim() !== '');
  const empty = $derived(!loading && !collections.length && !(offerPlaylists && playlists.length));

  $effect(() => {
    const opened = addToList.item;
    if (!opened) return;
    untrack(() => {
      chosen = {};
      newName = '';
      error = null;
      created = null;
      newKind = canCollect ? 'collection' : 'playlist';
      // Pas open na het laden: de focus hoort op de eerste lijst te landen, niet
      // op een veld waar de lijsten daarna boven verschijnen.
      void load().then(() => {
        if (addToList.item === opened) open = true;
      });
    });
  });

  $effect(() => {
    if (!open && untrack(() => addToList.item)) addToList.close();
  });

  async function load(): Promise<void> {
    loading = true;
    try {
      const api = listsApi(session.client);
      const query = { owned: true, sort: 'title', limit: 200 } as const;
      const [ownCollections, ownPlaylists] = await Promise.all([
        canCollect ? allPages((cursor) => api.collections({ ...query, ...(cursor ? { cursor } : {}) })) : [],
        canPlaylist ? allPages((cursor) => api.playlists({ ...query, ...(cursor ? { cursor } : {}) })) : []
      ]);
      collections = ownCollections;
      playlists = ownPlaylists;
    } catch (err) {
      error = describeError(err);
    } finally {
      loading = false;
    }
  }

  async function submit(): Promise<void> {
    const target = item;
    if (!target || busy) return;
    busy = true;
    error = null;
    const api = listsApi(session.client);
    const done: string[] = [];
    const failed: string[] = [];
    const add = async (kind: ListKind, id: string, title: string) => {
      try {
        await api.addItems(kind, id, [target.id]);
        done.push(title);
      } catch {
        failed.push(title);
      }
    };
    for (const list of collections) if (chosen[list.id]) await add('collection', list.id, list.title);
    for (const list of offerPlaylists ? playlists : []) if (chosen[list.id]) await add('playlist', list.id, list.title);
    const name = newName.trim();
    if (name) {
      try {
        const kind = newKind as ListKind;
        if (created?.name !== name || created.kind !== kind) {
          const list = kind === 'playlist' ? await api.createPlaylist(name) : await api.createCollection({ title: name });
          created = { name, kind, id: list.id, title: list.title };
        }
        await add(kind, created.id, created.title);
      } catch (err) {
        error = describeError(err);
      }
    }
    busy = false;
    if (failed.length || error) {
      const names = done.join(', ');
      error = error ?? t('lists.add.partial', { names: names || '-', failed: failed.join(', ') });
      return;
    }
    open = false;
    addToList.close();
    addToList.announce(t('lists.add.done', { names: done.join(', ') }));
  }
</script>

{#if item}
  <ConfirmDialog
    bind:open
    title={t('lists.add.for', { title: item.title })}
    confirmLabel={t('lists.add.action')}
    danger={false}
    {busy}
    disabled={!anyChosen}
    onconfirm={() => void submit()}
  >
    <div class="add">
      {#if !loading && collections.length && canCollect}
        <fieldset>
          <legend>{t('lists.add.collections')}</legend>
          {#each collections as list (list.id)}
            <label class="pick"><input type="checkbox" bind:checked={chosen[list.id]} disabled={busy} /><span>{list.title}</span></label>
          {/each}
        </fieldset>
      {/if}
      {#if !loading && offerPlaylists && playlists.length}
        <fieldset>
          <legend>{t('lists.add.playlists')}</legend>
          {#each playlists as list (list.id)}
            <label class="pick"><input type="checkbox" bind:checked={chosen[list.id]} disabled={busy} /><span>{list.title}</span></label>
          {/each}
        </fieldset>
      {/if}
      {#if empty}<p class="hint">{t('lists.add.none')}</p>{/if}
      {#if canPlaylist && !playable}<p class="hint">{t('lists.add.noPlaylistForKind')}</p>{/if}
      <div class="new">
        <Field label={t('lists.add.newName')} bind:value={newName} maxlength={200} disabled={busy} />
        {#if kinds.length > 1}
          <Select label={t('lists.add.newKind')} options={kinds} bind:value={newKind} disabled={busy} />
        {/if}
      </div>
      {#if error}<p class="error" role="alert">{error}</p>{/if}
    </div>
  </ConfirmDialog>
{/if}

{#if addToList.message}
  <div class="notice" role="status">{addToList.message}</div>
{/if}

<style>
  .add {
    display: flex;
    flex-direction: column;
    gap: 14px;
    max-height: 56dvh;
    overflow-y: auto;
  }

  fieldset {
    display: flex;
    flex-direction: column;
    margin: 0;
    padding: 0;
    border: 0;
  }

  legend {
    margin-bottom: 2px;
    font-size: 13px;
    color: var(--ink-2);
  }

  .pick {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 44px;
    font-size: 14px;
    color: var(--ink);
  }

  .pick span {
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .pick input {
    flex: none;
    width: 20px;
    height: 20px;
    accent-color: var(--ink);
  }

  .hint {
    margin: 0;
    font-size: 14px;
    color: var(--ink-3);
  }

  .new {
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .error {
    margin: 0;
    color: var(--danger-ink);
    font-size: 14px;
  }

  .notice {
    position: fixed;
    left: 50%;
    bottom: calc(var(--space-2) + env(safe-area-inset-bottom));
    z-index: 70;
    transform: translateX(-50%);
    max-width: min(480px, calc(100vw - 32px));
    padding: 10px 16px;
    border-radius: 999px;
    background: var(--ink);
    color: var(--bg);
    font-size: 14px;
    box-shadow: 0 8px 24px color-mix(in srgb, #000 40%, transparent);
  }

  @media (max-width: 899px) {
    .notice {
      bottom: calc(76px + env(safe-area-inset-bottom));
    }
  }
</style>
