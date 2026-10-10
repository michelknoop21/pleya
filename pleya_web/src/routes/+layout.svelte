<script lang="ts">
  import { onMount, type Snippet } from 'svelte';
  import { page } from '$app/state';
  import { goto } from '$app/navigation';
  import { dev } from '$app/environment';

  import '../styles/tokens.css';
  import '../styles/base.css';

  import TopNav from '$lib/components/TopNav.svelte';
  import MobileHeader from '$lib/components/MobileHeader.svelte';
  import TabBar from '$lib/components/TabBar.svelte';
  import StateView from '$lib/components/StateView.svelte';
  import SkeletonPage from '$lib/components/SkeletonPage.svelte';
  import { activeItemId, navItems } from '$lib/components/navItems';
  import { session } from '$lib/stores/session.svelte';
  import { theme } from '$lib/stores/theme.svelte';
  import { viewport } from '$lib/stores/viewport.svelte';
  import { pickLocale, setLocale, t } from '$lib/i18n';

  let { children }: { children: Snippet } = $props();

  const items = $derived(navItems(session.capabilities, session.libraries));
  const activeId = $derived(activeItemId(items, page.url.pathname, session.libraries));
  const showSearch = $derived(session.capabilities?.search === true);
  const searchActive = $derived(page.url.pathname.startsWith('/search'));
  // De primitievengalerij heeft geen server nodig en hoort niet achter de
  // sessiepoort; buiten `vite dev` is `dev` onwaar en valt deze tak weg.
  const isDevGallery = $derived(dev && page.url.pathname.startsWith('/dev/'));
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
    if (isDevGallery) return null;
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

{#if isDevGallery}
  <main id="main" class="dev-shell">
    {@render children()}
  </main>
{:else if session.phase === 'starting'}
  <SkeletonPage variant="compact" />
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
      <SkeletonPage variant="compact" />
    {/if}
  </main>
{:else if !routeMatchesPhase}
  <SkeletonPage variant="compact" />
{:else}
  <div class="shell" class:shell--wide={viewport.wide}>
    {#if viewport.wide}
      <TopNav {items} {activeId} {showSearch} {searchActive} />
    {:else}
      <MobileHeader {showSearch} {searchActive} />
    {/if}

    <main id="main" class="shell__main">
      {@render children()}
    </main>

    {#if !viewport.wide}
      <TabBar {items} {activeId} />
    {/if}
  </div>
{/if}

<style>
  .shell {
    min-height: 100dvh;
    display: flex;
    flex-direction: column;
  }

  .shell__main {
    flex: 1 1 auto;
    min-width: 0;
    padding-bottom: var(--space-3);
  }

  /* Ruimte voor de tabbalk, zodat de laatste rij niet eronder valt. */
  .shell:not(.shell--wide) .shell__main {
    padding-bottom: calc(
      var(--bottom-bar-height) + env(safe-area-inset-bottom, 0px) + var(--space-2)
    );
  }

  .dev-shell {
    min-height: 100dvh;
  }

  .auth-shell {
    min-height: 100dvh;
    display: grid;
    place-items: center;
    padding: var(--space-2) var(--space);
  }
</style>
