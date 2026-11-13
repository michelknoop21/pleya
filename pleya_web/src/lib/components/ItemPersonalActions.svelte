<script lang="ts">
  import { onDestroy } from 'svelte';
  import type { Item } from '../api/types';
  import { personalApi } from '../api/personal';
  import { describeError } from '../api/errors';
  import { session } from '../stores/session.svelte.js';
  import { addToList } from '../stores/addToList.svelte';
  import { t } from '../i18n';
  import ConfirmDialog from './ConfirmDialog.svelte';
  import Select from './Select.svelte';

  interface Props {
    item: Item;
    onchange: (next: Item) => void;
    /** Ronde icoonknoppen in plaats van tekstknoppen; de naam van de knop blijft dezelfde. */
    icons?: boolean;
  }
  let { item, onchange, icons = false }: Props = $props();
  const cls = $derived(icons ? 'ico' : 'btn btn--secondary');
  let active = true;
  onDestroy(() => { active = false; });
  let busy = $state(false);
  let error = $state<string | null>(null);
  let ratingOpen = $state(false);
  let draftRating = $state('');
  const canWatch = $derived(session.capabilities?.watch_state && (item.kind === 'movie' || item.kind === 'episode'));
  const canAdd = $derived(session.capabilities?.collections === true || session.capabilities?.playlists === true);
  const ratingOptions = $derived([
    { value: '', label: t('personal.noRating') },
    ...Array.from({ length: 10 }, (_, index) => ({ value: String(index + 1), label: `${index + 1}/10` }))
  ]);

  // Another item means another subject: a pending request or error of the previous one is not shown here.
  $effect(() => {
    void item.id;
    busy = false;
    error = null;
    ratingOpen = false;
  });

  async function change(operation: (api: ReturnType<typeof personalApi>, id: string) => Promise<Partial<Item>>): Promise<void> {
    if (busy) return;
    const id = item.id;
    busy = true;
    error = null;
    try {
      // Per action: the client carries the account generation, so one built at mount would refuse after a switch.
      const patch = await operation(personalApi(session.client), id);
      if (active && item.id === id) {
        onchange({ ...item, ...patch });
        ratingOpen = false;
      }
    } catch (err) {
      if (active && item.id === id) error = describeError(err);
    } finally {
      if (active && item.id === id) busy = false;
    }
  }
  function favorite(): void {
    if (!session.capabilities?.favorites) return;
    const next = !item.favorite;
    void change(async (api, id) => { await api.setFavorite(id, next); return { favorite: next }; });
  }
  function rate(): void {
    if (!session.capabilities?.ratings) return;
    const rating = draftRating === '' ? null : Number(draftRating);
    void change(async (api, id) => { await api.setRating(id, rating); return { rating }; });
  }
  function watched(): void {
    if (!canWatch) return;
    const next = !item.user_state?.watched;
    const duration = item.duration_ms ?? undefined;
    void change(async (api, id) => ({ user_state: await api.setWatched(id, next, duration) }));
  }
</script>

{#snippet face(label: string, path: string)}
  {#if icons}
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><path d={path} /></svg>
    <span class="visually-hidden">{label}</span>
  {:else}{label}{/if}
{/snippet}

<div class="personal-actions">
  {#if session.capabilities?.favorites}
    <button class={cls} aria-disabled={busy} aria-pressed={!!item.favorite} onclick={favorite}>
      {@render face(t(item.favorite ? 'personal.removeFavorite' : 'personal.addFavorite'), 'M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.5A4 4 0 0 1 19 10c0 5.6-7 10-7 10z')}
    </button>
  {/if}
  {#if session.capabilities?.ratings}
    <button class={cls} class:ico--on={icons && item.rating != null} aria-disabled={busy} onclick={() => { if (busy) return; draftRating = item.rating == null ? '' : String(item.rating); error = null; ratingOpen = true; }}>
      {@render face(item.rating == null ? t('personal.rate') : t('personal.rated', { rating: item.rating }), 'm12 4 2.5 5 5.5.8-4 3.9.9 5.5-4.9-2.6-4.9 2.6.9-5.5-4-3.9 5.5-.8z')}
    </button>
    <ConfirmDialog bind:open={ratingOpen} title={t('personal.yourRating')} confirmLabel={t('personal.save')} danger={false} {busy} onconfirm={rate}>
      <Select label={t('personal.rating')} options={ratingOptions} bind:value={draftRating} disabled={busy} />
      {#if error}<p role="alert">{error}</p>{/if}
    </ConfirmDialog>
  {/if}
  {#if canWatch}
    <button class={cls} class:ico--on={icons && !!item.user_state?.watched} aria-disabled={busy} onclick={watched}>
      {@render face(t(item.user_state?.watched ? 'personal.markUnwatched' : 'personal.markWatched'), 'm5 12 5 5 9-10')}
    </button>
  {/if}
  {#if canAdd}
    <button class={cls} aria-haspopup="dialog" onclick={() => addToList.open(item)}>{@render face(t('lists.add.title'), 'M12 5v14M5 12h14')}</button>
  {/if}
</div>
{#if error && !ratingOpen}<p role="alert">{error}</p>{/if}

<style>
  .personal-actions { display: flex; flex-wrap: wrap; gap: 8px; }
  .personal-actions:empty { display: none; }
  /* aria-disabled, not disabled: a disabled button drops keyboard focus while the request runs. */
  .personal-actions .btn[aria-disabled='true'],
  .personal-actions .ico[aria-disabled='true'] { opacity: 0.5; cursor: progress; }
  .personal-actions:has(.ico) { gap: 12px; }
  .ico {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    flex: none;
    width: 48px;
    height: 48px;
    padding: 0;
    border: 1px solid color-mix(in srgb, var(--text) 30%, transparent);
    border-radius: 50%;
    background: color-mix(in srgb, var(--bg) 50%, transparent);
    color: var(--ink);
    cursor: pointer;
  }
  .ico svg { width: 20px; height: 20px; }
  .ico[aria-pressed='true'], .ico--on { background: var(--ink); border-color: var(--ink); color: var(--bg); }
</style>
