<!--
  Een lijst maken of bewerken. Bij een verzameling hoort de zichtbaarheid (vraag
  30): alleen ik, iedereen, of gekozen gebruikers.

  Delen is voor eigenaar en beheerder (hoofdstuk 14c). Een lid of beperkte
  gebruiker houdt zijn verzamelingen privé: hij krijgt de keuze niet te zien, er
  gaat geen zichtbaarheid mee en er komt geen `GET /users`. Staat een eigen lijst
  nog gedeeld van toen hij die rol had, dan blijft alleen de weg terug: de huidige
  stand of privé. Is de zichtbaarheid onbekend (3.2), dan staat er een uitleg en
  gaat er geen waarde mee terug.
-->
<script lang="ts">
  import { untrack } from 'svelte';
  import ConfirmDialog from '../ConfirmDialog.svelte';
  import Field from '../Field.svelte';
  import Choice from '../Choice.svelte';
  import Alert from '../Alert.svelte';
  import type { Collection, Playlist, User } from '../../api/types';
  import { describeError } from '../../api/errors';
  import { knownVisibility, listsApi, type ListKind } from '../../api/lists';
  import { session } from '../../stores/session.svelte';
  import { t } from '../../i18n';

  interface Props {
    open?: boolean;
    kind: ListKind;
    /** Leeg maakt een nieuwe lijst. */
    list?: Collection | Playlist | null;
    onsaved: (list: Collection | Playlist) => void;
  }

  let { open = $bindable(false), kind, list = null, onsaved }: Props = $props();

  let name = $state('');
  let visibility = $state('private');
  let recipients = $state<string[]>([]);
  let users = $state<User[]>([]);
  let busy = $state(false);
  let error = $state<string | null>(null);

  const collection = $derived(kind === 'collection' ? (list as Collection | null) : null);
  const unknown = $derived(collection ? knownVisibility(collection.visibility) === null : false);
  const canShare = $derived(session.canAdminister);
  const visibilityOptions = $derived([
    { value: 'private', label: t('lists.form.private') },
    { value: 'everyone', label: t('lists.form.everyone') },
    { value: 'users', label: t('lists.form.users') }
  ]);
  const canRevoke = $derived(!canShare && !unknown && collection?.is_owner === true && collection.visibility !== 'private');
  const revokeOptions = $derived(visibilityOptions.filter((option) => option.value === 'private' || option.value === collection?.visibility));
  const others = $derived(users.filter((user) => user.id !== session.me?.id));
  const dialogTitle = $derived(
    list
      ? t('lists.form.editTitle', { title: list.title })
      : t(kind === 'collection' ? 'lists.form.collectionTitle' : 'lists.form.playlistTitle')
  );

  $effect(() => {
    if (!open) return;
    untrack(() => {
      name = list?.title ?? '';
      visibility = collection?.visibility ?? 'private';
      recipients = collection?.shared_with?.map((user) => user.id) ?? [];
      error = null;
      if (kind === 'collection' && canShare) void loadUsers();
    });
  });

  async function loadUsers(): Promise<void> {
    try {
      const page = await session.client.request((raw) => raw.GET('/users'));
      users = page.items;
    } catch {
      users = [];
    }
  }

  function toggle(id: string, on: boolean): void {
    recipients = on ? [...recipients, id] : recipients.filter((other) => other !== id);
  }

  function collectionBody() {
    if (unknown) return {};
    if (canRevoke) return visibility === 'private' ? { visibility: 'private' as const } : {};
    if (!canShare) return {};
    return { visibility: visibility as 'private' | 'everyone' | 'users', ...(visibility === 'users' ? { shared_with: recipients } : {}) };
  }

  async function submit(): Promise<void> {
    if (busy) return;
    busy = true;
    error = null;
    try {
      const api = listsApi(session.client);
      const title = name.trim();
      let saved: Collection | Playlist;
      if (kind === 'playlist') saved = list ? await api.updatePlaylist(list.id, title) : await api.createPlaylist(title);
      else if (list) saved = await api.updateCollection(list.id, { title, ...collectionBody() });
      else saved = await api.createCollection({ title, ...collectionBody() });
      open = false;
      onsaved(saved);
    } catch (err) {
      error = describeError(err);
    } finally {
      busy = false;
    }
  }
</script>

<ConfirmDialog
  bind:open
  title={dialogTitle}
  confirmLabel={list ? t('lists.form.save') : t('lists.form.create')}
  danger={false}
  {busy}
  disabled={!name.trim()}
  onconfirm={() => void submit()}
>
  <div class="form">
    <Field label={t('lists.form.name')} bind:value={name} maxlength={200} required disabled={busy} />
    {#if kind === 'collection'}
      {#if unknown}
        <Alert tone="info" live={false}>{t('lists.form.unknownVisibility')}</Alert>
      {:else if canShare}
        <Choice legend={t('lists.form.visibility')} options={visibilityOptions} bind:value={visibility} disabled={busy} />
        {#if visibility === 'users'}
          <fieldset class="people">
            <legend>{t('lists.form.recipients')}</legend>
            {#each others as user (user.id)}
              <label class="person">
                <input type="checkbox" checked={recipients.includes(user.id)} disabled={busy} onchange={(event) => toggle(user.id, event.currentTarget.checked)} />
                {user.username}
              </label>
            {:else}
              <p>{t('lists.form.noRecipients')}</p>
            {/each}
          </fieldset>
        {/if}
      {:else if canRevoke}
        <Choice legend={t('lists.form.visibility')} options={revokeOptions} bind:value={visibility} disabled={busy} />
      {/if}
    {/if}
    {#if error}<p class="error" role="alert">{error}</p>{/if}
  </div>
</ConfirmDialog>

<style>
  .form {
    display: flex;
    flex-direction: column;
    gap: 14px;
  }

  .people {
    display: flex;
    flex-direction: column;
    margin: 0;
    padding: 0;
    border: 0;
  }

  .people legend {
    margin-bottom: 4px;
    font-size: 13px;
    color: var(--ink-2);
  }

  .person {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 44px;
    font-size: 14px;
    color: var(--ink);
  }

  .person input {
    width: 20px;
    height: 20px;
    accent-color: var(--ink);
  }

  .people p {
    margin: 0;
    font-size: 14px;
    color: var(--ink-3);
  }

  .error {
    margin: 0;
    color: var(--danger-ink);
    font-size: 14px;
  }
</style>
