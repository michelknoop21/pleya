<script lang="ts">
  import { onDestroy } from 'svelte';
  import type { Item } from '../api/types';
  import { personalApi } from '../api/personal';
  import { describeError } from '../api/errors';
  import { session } from '../stores/session.svelte.js';
  import { t } from '../i18n';
  import ConfirmDialog from './ConfirmDialog.svelte';
  import Select from './Select.svelte';

  let { item, onchange }: { item: Item; onchange: (next: Item) => void } = $props();
  let active = true;
  onDestroy(() => { active = false; });
  let busy = $state(false);
  let error = $state<string | null>(null);
  let ratingOpen = $state(false);
  let draftRating = $state('');
  const canWatch = $derived(session.capabilities?.watch_state && (item.kind === 'movie' || item.kind === 'episode'));
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

<div class="personal-actions">
  {#if session.capabilities?.favorites}
    <button class="btn btn--secondary" aria-disabled={busy} aria-pressed={!!item.favorite} onclick={favorite}>
      {t(item.favorite ? 'personal.removeFavorite' : 'personal.addFavorite')}
    </button>
  {/if}
  {#if session.capabilities?.ratings}
    <button class="btn btn--secondary" aria-disabled={busy} onclick={() => { if (busy) return; draftRating = item.rating == null ? '' : String(item.rating); error = null; ratingOpen = true; }}>
      {item.rating == null ? t('personal.rate') : t('personal.rated', { rating: item.rating })}
    </button>
    <ConfirmDialog bind:open={ratingOpen} title={t('personal.yourRating')} confirmLabel={t('personal.save')} danger={false} {busy} onconfirm={rate}>
      <Select label={t('personal.rating')} options={ratingOptions} bind:value={draftRating} disabled={busy} />
      {#if error}<p role="alert">{error}</p>{/if}
    </ConfirmDialog>
  {/if}
  {#if canWatch}
    <button class="btn btn--secondary" aria-disabled={busy} onclick={watched}>
      {t(item.user_state?.watched ? 'personal.markUnwatched' : 'personal.markWatched')}
    </button>
  {/if}
</div>
{#if error && !ratingOpen}<p role="alert">{error}</p>{/if}

<style>
  .personal-actions { display: flex; flex-wrap: wrap; gap: 8px; }
  .personal-actions:empty { display: none; }
  /* aria-disabled, not disabled: a disabled button drops keyboard focus while the request runs. */
  .personal-actions .btn[aria-disabled='true'] { opacity: 0.5; cursor: progress; }
</style>
