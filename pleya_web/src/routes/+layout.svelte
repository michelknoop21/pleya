<script lang="ts">
  import { onMount, type Snippet } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';

  import '../styles/tokens.css';
  import '../styles/base.css';

  import NavRail from '$lib/components/NavRail.svelte';
  import BottomBar from '$lib/components/BottomBar.svelte';
  import StateView from '$lib/components/StateView.svelte';
  import ThemePicker from '$lib/components/ThemePicker.svelte';
  import { activeItemId, navItems } from '$lib/components/navItems';
  import { session } from '$lib/stores/session.svelte';
  import { theme } from '$lib/stores/theme.svelte';
  import { viewport } from '$lib/stores/viewport.svelte';
  import { pickLocale, setLocale, t } from '$lib/i18n';

  let { children }: { children: Snippet } = $props();

  const items = $derived(navItems(session.capabilities, session.libraries.length));
  const activeId = $derived(activeItemId(items, page.url.pathname));
  const isAuthRoute = $derived(
    page.url.pathname === '/login' || page.url.pathname === '/setup'
  );

  onMount(() => {
    setLocale(pickLocale(navigator.languages ?? [navigator.language]));
    const stopTheme = theme.start();
    const stopViewport = viewport.start();
    void session.start();
    return () => {
      stopTheme();
      stopViewport();
    };
  });

  /**
   * Waar de gebruiker hoort te zijn, gegeven de toestand van de sessie.
   *
   * `null` betekent: hier is niets mis mee, blijf staan.
   */
  const expectedPath = $derived.by(() => {
    if (session.phase === 'setup') return '/setup';
    if (session.phase === 'signed-out') return '/login';
    if (session.phase === 'ready' && isAuthRoute) return '/';
    return null;
  });

  /**
   * Of de huidige route bij de toestand past.
   *
   * Dit is meer dan een cosmetische controle. `goto` is asynchroon, dus tussen
   * "de sessie is er niet" en "de browser staat op /login" zit een frame
   * waarin de oude pagina nog gemonteerd is. Rendert die pagina in dat frame,
   * dan doet hij zijn aanvraag alsnog, krijgt een 401, en dat telt als een
   * verloren sessie terwijl er nooit een was — waarna een server die nog
   * opgezet moet worden een inlogscherm laat zien. Niets renderen tot de route
   * klopt is de enige plek waar dat sluitend te maken is.
   */
  const routeMatchesPhase = $derived(expectedPath === null);

  // De schil stuurt zelf naar setup of inloggen. Dat is geen routebewaking op
  // de server: de bundel is statisch en iedereen kan elk pad opvragen. Wat
  // beschermt is de API, die zonder geldig token niets geeft.
  $effect(() => {
    const target = expectedPath;
    if (target !== null && page.url.pathname !== target) {
      void goto(target, { replaceState: true });
    }
  });

  $effect(() => {
    document.documentElement.dataset['theme'] = theme.palette;
  });
</script>

<svelte:head>
  <title>{t('app.name')}</title>
</svelte:head>

<a class="skip-link" href="#main">{t('nav.skipToContent')}</a>

{#if session.phase === 'starting'}
  <StateView kind="loading" />
{:else if session.phase === 'unreachable'}
  <StateView
    kind="error"
    title={t('unreachable.title')}
    message={session.error ?? undefined}
    onRetry={() => session.start()}
  />
{:else if session.phase === 'setup' || session.phase === 'signed-out'}
  <main id="main" class="auth-shell">
    {#if page.url.pathname === expectedPath}
      {@render children()}
    {:else}
      <StateView kind="loading" />
    {/if}
  </main>
{:else if !routeMatchesPhase}
  <StateView kind="loading" />
{:else}
  <div class="shell" class:shell--wide={viewport.wide}>
    {#if viewport.wide}
      <NavRail {items} {activeId} />
    {/if}

    <div class="shell__body">
      <header class="shell__top">
        {#if !viewport.wide}
          <a class="shell__brand" href="/">
            <img src="/brand/pleya-mark-64.png" alt="" width="28" height="28" />
            <span>{t('app.name')}</span>
          </a>
        {:else}
          <span></span>
        {/if}
        <ThemePicker />
      </header>

      <main id="main" class="shell__main">
        {@render children()}
      </main>
    </div>

    {#if !viewport.wide}
      <BottomBar {items} {activeId} />
    {/if}
  </div>
{/if}

<style>
  .shell {
    display: flex;
    min-height: 100dvh;
    align-items: flex-start;
  }

  .shell__body {
    flex: 1 1 auto;
    min-width: 0;
    display: flex;
    flex-direction: column;
  }

  .shell__top {
    position: sticky;
    top: 0;
    z-index: 10;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--space);
    padding: var(--space-half) var(--page-inset, var(--space));
    background: color-mix(in srgb, var(--bg) 88%, transparent);
    backdrop-filter: blur(18px);
    -webkit-backdrop-filter: blur(18px);
    min-height: 56px;
  }

  .shell__brand {
    display: inline-flex;
    align-items: center;
    gap: var(--space-half);
    font-weight: 700;
    letter-spacing: -0.2px;
  }

  .shell__main {
    flex: 1 1 auto;
    min-width: 0;
    padding-bottom: var(--space-3);
  }

  /* Ruimte voor de bottom bar, zodat de laatste rij niet onder de balk valt. */
  .shell:not(.shell--wide) .shell__main {
    padding-bottom: calc(var(--bottom-bar-height) + env(safe-area-inset-bottom, 0px) + var(--space-2));
  }

  .auth-shell {
    min-height: 100dvh;
    display: grid;
    place-items: center;
    padding: var(--space-2) var(--space);
  }

  :global(:root) {
    --page-inset: 16px;
  }

  @media (min-width: 900px) {
    :global(:root) {
      --page-inset: 24px;
    }
  }

  @media (min-width: 1200px) {
    :global(:root) {
      --page-inset: 32px;
    }
  }
</style>
