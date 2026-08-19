<!--
  De enige plek waar een afbeelding binnenkomt.

  `GET /pleya/v1/artwork/{id}` is klasse `authenticated` en accepteert alleen
  een Authorization-header (`internal/api/server.go`). Een `<img src>` kan die
  niet zetten, en een service worker die hem injecteert vraagt een secure
  context, wat `http://nas:8832` op een LAN niet is. De bytes komen daarom via
  `fetch` binnen en gaan als object-URL aan het element.

  Vier dingen die dat vraagt en die hier bij elkaar staan, omdat ze los van
  elkaar stil lekken:

    1. niet vooraf laden. Een raster van vijfhonderd posters mag geen
       vijfhonderd aanvragen doen; een IntersectionObserver laadt wat in beeld
       komt, met marge zodat er niets zichtbaar inpopt.
    2. annuleren. Verlaat een kaart het scherm voordat de bytes binnen zijn,
       dan wordt de aanvraag afgebroken in plaats van uitgeserveerd.
    3. vrijgeven. Elke object-URL wordt precies één keer ingetrokken: bij een
       nieuwe bron en bij het opruimen van de component. Zonder dat groeit het
       browsergeheugen bij elke navigatie door.
    4. toestand. Laden, mislukt en "er is geen afbeelding" zijn drie
       verschillende dingen en zien er alle drie anders uit.
-->
<script lang="ts">
  import { onDestroy, untrack } from 'svelte';
  import { session } from '../stores/session.svelte';
  import { t } from '../i18n';

  interface Props {
    artworkId: string | null | undefined;
    alt: string;
    /** Bepaalt de verhouding van het vlak: poster is 2:3, wide is 16:9. */
    shape?: 'poster' | 'wide' | 'free';
    /** Hoe ver buiten beeld er alvast geladen wordt. */
    rootMargin?: string;
    /** Zet de luie strategie uit voor beeld dat altijd meteen zichtbaar is. */
    eager?: boolean;
    /** Vlak zonder ronde hoeken, voor beeld dat de volle breedte vult. */
    flat?: boolean;
  }

  let {
    artworkId,
    alt,
    shape = 'poster',
    rootMargin = '400px',
    eager = false,
    flat = false
  }: Props = $props();

  let host = $state<HTMLDivElement | null>(null);
  let objectUrl = $state<string | null>(null);
  let status = $state<'idle' | 'loading' | 'loaded' | 'error'>('idle');
  // `eager` is een prop en verandert niet gedurende het leven van deze
  // component; de beginwaarde is dus de juiste startwaarde.
  let visible = $state(untrack(() => eager));

  let controller: AbortController | null = null;
  let currentUrl: string | null = null;

  function release(): void {
    if (currentUrl) {
      URL.revokeObjectURL(currentUrl);
      currentUrl = null;
    }
    objectUrl = null;
  }

  function abort(): void {
    controller?.abort();
    controller = null;
  }

  async function load(id: string): Promise<void> {
    abort();
    release();
    status = 'loading';
    const own = new AbortController();
    controller = own;
    try {
      const blob = await session.client.artworkBlob(id, own.signal);
      if (own.signal.aborted) return;
      const url = URL.createObjectURL(blob);
      currentUrl = url;
      objectUrl = url;
      status = 'loaded';
    } catch {
      if (own.signal.aborted) return;
      // Een artwork-id dat de server niet heeft is een normale toestand: in v1
      // levert hij uitsluitend afbeeldingen die naast de media op schijf staan.
      status = 'error';
    } finally {
      if (controller === own) controller = null;
    }
  }

  // De waarnemer bestaat alleen zolang het element nog niet in beeld is
  // geweest; daarna heeft hij niets meer te doen.
  $effect(() => {
    if (eager || visible || !host) return;
    if (typeof IntersectionObserver !== 'function') {
      visible = true;
      return;
    }
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            visible = true;
            observer.disconnect();
          }
        }
      },
      { rootMargin }
    );
    observer.observe(host);
    return () => observer.disconnect();
  });

  $effect(() => {
    const id = artworkId;
    if (!visible) return;
    if (!id) {
      abort();
      release();
      status = 'idle';
      return;
    }
    void load(id);
  });

  onDestroy(() => {
    abort();
    release();
  });
</script>

<div
  bind:this={host}
  class="artwork artwork--{shape}"
  class:artwork--loading={status === 'loading'}
  class:artwork--flat={flat}
>
  {#if objectUrl}
    <img src={objectUrl} {alt} decoding="async" />
  {:else if status === 'error' || (!artworkId && visible)}
    <div class="artwork__fallback" role="img" aria-label={alt || t('artwork.none')}>
      <svg viewBox="0 0 24 24" aria-hidden="true" focusable="false">
        <path
          fill="currentColor"
          d="M4 4h16v16H4zm2 2v9.2l3.4-3.4 3.1 3.1 3.1-3.1L18 13.9V6zm0 12h12v-1.3l-2.4-2.4-3.1 3.1-3.1-3.1L6 16.9z"
        />
      </svg>
    </div>
  {/if}
</div>

<style>
  .artwork {
    position: relative;
    overflow: hidden;
    background: var(--skeleton);
    width: 100%;
    border-radius: var(--radius-sm);
  }

  /* Ronde hoeken horen bij het vlak zelf en niet bij een stijl per instantie:
     een style-attribuut per kaart zou de strikte style-src uit de CSP breken. */
  .artwork--flat {
    border-radius: 0;
  }

  .artwork--poster {
    aspect-ratio: var(--aspect-poster);
  }

  .artwork--wide {
    aspect-ratio: var(--aspect-episode);
  }

  .artwork img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    animation: artwork-in var(--dur-normal) var(--ease);
  }

  .artwork--loading::after {
    content: '';
    position: absolute;
    inset: 0;
    background: linear-gradient(
      90deg,
      transparent,
      color-mix(in srgb, var(--text) 6%, transparent),
      transparent
    );
    animation: artwork-shimmer 1.2s infinite;
  }

  .artwork__fallback {
    display: grid;
    place-items: center;
    width: 100%;
    height: 100%;
    color: var(--text-muted);
  }

  .artwork__fallback svg {
    width: 32%;
    max-width: 48px;
    opacity: 0.5;
  }

  @keyframes artwork-in {
    from {
      opacity: 0;
    }
    to {
      opacity: 1;
    }
  }

  @keyframes artwork-shimmer {
    from {
      transform: translateX(-100%);
    }
    to {
      transform: translateX(100%);
    }
  }

  @media (prefers-reduced-motion: reduce) {
    .artwork img {
      animation: none;
    }
    .artwork--loading::after {
      animation: none;
    }
  }
</style>
