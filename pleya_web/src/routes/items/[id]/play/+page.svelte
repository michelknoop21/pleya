<!--
  /items/{id}/play: de browserspeler (S13.2, S18.3). `?version=` kiest een
  versie, `?audio=` en `?subtitle=` een spoor voor deze ene afspeelactie (de
  keuzelijsten op het filmdetail), `?t=` een hervatpositie in seconden; die komt van de knop "Verder
  vanaf" op de detailpagina, die hem uit `user_state.position_ms` leest. De
  speler rapporteert kijkstatus pas na werkelijk afspelen (S13.3).

  De route laadt het item voor titel, duur en sporen; het afspeelpad zelf loopt
  in Player via `POST /playback/plan`. Bij een aflevering leest hij ook het
  seizoen en de serie (de kop) en de aflevering die volgt; een titel waar niets
  op volgt krijgt het slotscherm.
-->
<script lang="ts">
  import { page } from '$app/state';
  import { goto } from '$app/navigation';

  import Player from '#lib/player/Player.svelte';
  import PlayerEndScreen from '#lib/player/PlayerEndScreen.svelte';
  import { nextEpisode } from '#lib/player/upNext.js';
  import { videoContext, type VideoContext } from '#lib/util/videoContext.js';
  import { browserPlayerDeps } from '#lib/player/browserDeps.js';
  import StateView from '#lib/components/StateView.svelte';
  import SkeletonPage from '#lib/components/SkeletonPage.svelte';
  import { session } from '#lib/stores/session.svelte.js';
  import { listsApi, nextInList } from '#lib/api/lists.js';
  import { playerHref } from '#lib/player/route.js';
  import { describeError } from '#lib/api/errors.js';
  import type { Item } from '#lib/api/types.js';
  import { t } from '#lib/i18n/index.js';

  const itemId = $derived(page.params['id'] ?? '');
  // De keuzes uit de URL horen bij het item dat speelt. Tussen `goto` naar de
  // volgende aflevering en het laden ervan wijst de URL al naar het nieuwe item
  // terwijl het oude nog speelt; uit de live URL lezen zou dan de speler voor
  // het oude item opnieuw opbouwen (andere versie, vanaf 0) en kijkstatus voor
  // dat item laten schrijven. Daarom worden ze vastgelegd zodra het item laadt.
  type Picks = { version: string | null; startAt: number; audio: string | null; subtitle: string | null };
  function readPicks(): Picks {
    const query = page.url.searchParams;
    const raw = Number(query.get('t') ?? 0);
    return {
      version: query.get('version'),
      startAt: Number.isFinite(raw) && raw > 0 ? Math.floor(raw) : 0,
      audio: query.get('audio'),
      subtitle: query.get('subtitle')
    };
  }
  let picks = $state<Picks>({ version: null, startAt: 0, audio: null, subtitle: null });
  const versionParam = $derived(picks.version);
  const startAt = $derived(picks.startAt);

  let item = $state<Item | null>(null);
  let error = $state<string | null>(null);
  let context = $state<VideoContext>({});
  /** `undefined` zolang de vraag loopt: dan komt er geen kaart en ook geen slotscherm. */
  let next = $state<Item | null | undefined>(undefined);
  let shell = $state<HTMLElement | null>(null);

  // Het oude item blijft staan tot het nieuwe er is: de speler, en daarmee volledig scherm, valt niet weg.
  async function load(id: string, signal: AbortSignal): Promise<void> {
    error = null;
    try {
      const loaded = await session.client.item(id, signal);
      if (signal.aborted) return;
      picks = readPicks();
      item = loaded;
      void loadAround(loaded, signal);
    } catch (err) {
      if (!signal.aborted) error = describeError(err);
    }
  }

  // Kop en volgende aflevering zijn aankleding: mislukt het lezen, dan speelt de titel gewoon.
  async function loadAround(current: Item, signal: AbortSignal): Promise<void> {
    context = {};
    next = undefined;
    const around = await videoContext(current, (id, s) => session.client.item(id, s), signal);
    if (signal.aborted) return;
    context = around;
    const following = await nextEpisode((id, query, s) => session.client.children(id, query, s), current, around.season, signal).catch(() => undefined);
    if (!signal.aborted) next = following;
  }

  const heading = $derived(context.show?.title ?? item?.title ?? '');
  const subheading = $derived.by(() => {
    if (item?.kind !== 'episode') return null;
    const code = typeof context.season?.index === 'number' && typeof item.index === 'number'
      ? t('card.episodeCode', { season: context.season.index, episode: item.index })
      : null;
    return [code, item.title].filter(Boolean).join(' · ');
  });

  $effect(() => {
    const id = itemId;
    if (!id) return;
    const controller = new AbortController();
    void load(id, controller.signal);
    return () => controller.abort();
  });

  const version = $derived(
    versionParam !== null ? item?.versions?.find((v) => v.id === versionParam) : item?.versions?.[0]
  );

  function close(): void {
    void goto(`/items/${encodeURIComponent(itemId)}`);
  }

  // Binnen een afspeellijst gaat het volgende item door. Lukt het lezen niet, dan
  // blijft de speler op het einde staan: de film is af, er is niets kapot.
  const playlistId = $derived(page.url.searchParams.get('playlist'));
  async function playNext(): Promise<void> {
    const list = playlistId;
    if (!list) return;
    try {
      const next = nextInList(await listsApi(session.client).allItems('playlist', list), itemId);
      if (next) await goto(playerHref(next, undefined, undefined, list), { replaceState: true });
    } catch {
      // Zie boven.
    }
  }

  function playFollowing(): Promise<void> | undefined {
    return next ? goto(playerHref(next.id), { replaceState: true }) : undefined;
  }

  // De schil stuurt bij `signed-out` zelf naar /login.
  function login(): void {
    session.signOut();
  }
</script>

<svelte:head><title>{item?.title ?? t('player.title')} · {t('app.name')}</title></svelte:head>

<!-- Volledig scherm hangt aan deze schil: die blijft staan als de speler voor een volgende aflevering wisselt. -->
<div bind:this={shell}>
{#if error}
  <div class="play-state">
    <StateView kind="error" message={error} onRetry={() => void load(itemId, new AbortController().signal)} />
  </div>
{:else if !item}
  <SkeletonPage variant="compact" />
{:else if versionParam !== null && !version}
  <div class="play-state">
    <StateView kind="error" message={t('item.versionMissing')}>
      {#snippet actions()}<a class="btn" href={`/items/${encodeURIComponent(itemId)}`}>{t('item.title')}</a>{/snippet}
    </StateView>
  </div>
{:else}
  {#key `${item.id}:${version?.id ?? ''}`}
    <Player
      {item}
      {version}
      {startAt}
      audioId={picks.audio}
      subtitleId={picks.subtitle}
      deps={browserPlayerDeps(session.client, session.capabilities)}
      onclose={close}
      onlogin={login}
      onfinished={playlistId ? () => void playNext() : undefined}
      heading={item.kind === 'episode' ? heading : null}
      {subheading}
      next={playlistId ? null : next ?? null}
      onnext={playFollowing}
      fullscreenTarget={shell}
      end={next === null && !playlistId ? endScreen : undefined}
    />
  {/key}
{/if}
</div>

{#snippet endScreen({ replay }: { replay: () => void })}
  {#if item}
    <PlayerEndScreen {item} {heading} {subheading} onchange={(changed) => (item = changed)} onreplay={replay} />
  {/if}
{/snippet}

<style>
  .play-state {
    padding: var(--space-3) var(--inset);
  }
</style>
