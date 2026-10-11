<!--
  De server antwoordt niet (beeld 14). Dit is geen uitlogscherm: er kwam geen
  401, dus de sessie is niet verloren, en de staat zegt dat ook als er een
  refreshtoken is.

  Opnieuw proberen gaat vanzelf, na 2, 4, 8 en 16 s en daarna elke 30 s, zonder
  bovengrens: een NAS die herstart komt na een paar minuten terug, en dan hoort
  de app er weer te zijn zonder dat iemand op een knop drukt. De knop stopt de
  lopende aftelling, probeert meteen en begint de reeks daarna weer bij 2.

  Toegankelijkheid: het getal van de aftelling staat buiten elke live-regio,
  anders praat een schermlezer elke seconde. Alleen "Verbinding maken…" komt in
  een statusregel, zodat de overgang naar een poging wel te horen is. Daarom is
  de staat ook geen alert (StateView `alert`): binnen een alert zou de aftelling
  alsnog voorgelezen worden.

  De tweede knop uit 14 ("Wat kan er aan de hand zijn?") staat er niet: er is
  geen hulppagina om naar te verwijzen, en een knop zonder bestemming belooft
  iets wat er niet is.
-->
<script lang="ts">
  import { onMount } from 'svelte';
  import StateView from './StateView.svelte';
  import { t } from '../i18n';
  import { formatRelative } from '../util/format';
  import { retryDelay } from '../util/retrySchedule';

  interface Props {
    /** Servernaam uit het bewaarde record; zonder record de host. */
    name: string;
    host: string;
    /** RFC 3339 van de laatste geslaagde aanvraag, of null zonder record. */
    lastContactAt: string | null;
    /** Of de tokenopslag nog een refreshtoken heeft. */
    signedIn: boolean;
    /** Eén poging. Lukt hij, dan haalt de layout deze staat weg. */
    onRetry: () => Promise<void>;
  }

  let { name, host, lastContactAt, signedIn, onRetry }: Props = $props();

  let attempt = 0;
  let remaining = $state(retryDelay(0));
  let busy = $state(false);
  let now = $state(Date.now());
  let timer: ReturnType<typeof setInterval> | undefined;
  let mounted = false;

  const lastContact = $derived(formatRelative(lastContactAt, now));
  // De zin wordt op `{host}` gesplitst en niet in twee sleutels geknipt: zo
  // blijft hij één vertaalbare eenheid, ook in een taal waar de host vooraan staat.
  const [addressBefore = '', addressAfter = ''] = t('unreachable.address').split('{host}');

  function stop(): void {
    if (timer !== undefined) clearInterval(timer);
    timer = undefined;
  }

  function countdown(): void {
    stop();
    remaining = retryDelay(attempt);
    timer = setInterval(() => {
      now = Date.now();
      remaining -= 1;
      if (remaining <= 0) {
        attempt += 1;
        void tryNow();
      }
    }, 1000);
  }

  async function tryNow(): Promise<void> {
    stop();
    busy = true;
    try {
      await onRetry();
    } finally {
      busy = false;
      now = Date.now();
      // Na een geslaagde poging is deze staat al ontkoppeld; dan geen nieuwe timer.
      if (mounted) countdown();
    }
  }

  function retryNow(): void {
    if (busy) return;
    attempt = 0;
    void tryNow();
  }

  onMount(() => {
    mounted = true;
    countdown();
    return () => {
      mounted = false;
      stop();
    };
  });
</script>

<div class="unreachable">
  <StateView
    title={t('unreachable.title', { name })}
    level={1}
    alert={false}
  >
    {#snippet icon()}
      <!-- Het pad van `cloudoff` uit de northstar (src/build.mjs). -->
      <svg viewBox="0 0 24 24" focusable="false" class="unreachable__icon">
        <path d="M7 18h10a4 4 0 0 0 .8-7.9A6 6 0 0 0 6.6 9 4.5 4.5 0 0 0 7 18z" />
        <path d="m4 4 16 16" />
      </svg>
    {/snippet}

    {#snippet body()}
      <p class="unreachable__text">
        {addressBefore}<span class="unreachable__host">{host}</span>{addressAfter}
        {#if signedIn}{' '}{t('unreachable.signedIn')}{/if}
      </p>
      <p class="unreachable__meta">
        {#if lastContact}
          <span>{t('unreachable.lastContact', { when: lastContact })}</span>
          <span aria-hidden="true">·</span>
        {/if}
        <span class="visually-hidden" role="status">{busy ? t('unreachable.connecting') : ''}</span>
        {#if busy}
          <span aria-hidden="true">{t('unreachable.connecting')}</span>
        {:else}
          <span>{t('unreachable.countdown', { seconds: remaining })}</span>
        {/if}
      </p>
    {/snippet}

    {#snippet actions()}
      <button type="button" class="btn btn--sm" onclick={retryNow} aria-disabled={busy}>
        <svg viewBox="0 0 24 24" focusable="false" aria-hidden="true" class="unreachable__btn-icon">
          <path d="M20 12a8 8 0 1 1-2.3-5.7" />
          <path d="M20 4v5h-5" />
        </svg>
        {t('unreachable.retryNow')}
      </button>
    {/snippet}
  </StateView>
</div>

<style>
  /* 14 zet de staat lager dan een gewone lege staat: 120 boven in plaats van
     64, want er staat geen paginakop boven. */
  .unreachable :global(.state) {
    padding-top: 120px;
  }

  .unreachable__icon,
  .unreachable__btn-icon {
    fill: none;
    stroke: currentColor;
    stroke-width: 2;
    stroke-linecap: round;
    stroke-linejoin: round;
  }

  .unreachable__btn-icon {
    width: 16px;
    height: 16px;
    flex: 0 0 auto;
  }

  .unreachable__text {
    margin: 8px 0 0;
    font-size: 14px;
    line-height: 1.45;
  }

  .unreachable__host {
    font-family: var(--font-mono);
    font-size: 0.92em;
  }

  /* `.dim` uit 14: 13 in --ink-3, 10 onder de uitleg. */
  .unreachable__meta {
    margin: 10px 0 0;
    font-size: 13px;
    line-height: 1.45;
    color: var(--ink-3);
  }
</style>
