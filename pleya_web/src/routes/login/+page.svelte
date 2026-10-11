<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import Field from '$lib/components/Field.svelte';
  import { session } from '$lib/stores/session.svelte';
  import { ApiError, describeError } from '$lib/api/errors';
  import { t } from '$lib/i18n';

  let username = $state('');
  let password = $state('');
  let busy = $state(false);
  let error = $state<string | null>(null);

  const valid = $derived(username.trim().length > 0 && password.length > 0);

  async function submit(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (!valid || busy) return;
    busy = true;
    error = null;
    try {
      await session.client.login({ username: username.trim(), password });
      await session.afterAuth();
      await goto('/', { replaceState: true });
    } catch (err) {
      if (err instanceof ApiError && err.code === 'auth.rate_limited') {
        // De server geeft retry_after_ms mee in details. Dat is het enige
        // getal dat hier iets betekent; zelf een wachttijd verzinnen zou naast
        // de emmer van de server zitten.
        const seconds = Math.ceil((err.retryAfterMs ?? 0) / 1000);
        error = t('login.rateLimited', { seconds });
      } else {
        error = describeError(err);
      }
    } finally {
      busy = false;
    }
  }
</script>

<svelte:head><title>{t('login.title')} · {t('app.name')}</title></svelte:head>

<!--
  Beeld 12, met het vlak volgens de keuze voor het inlogscherm (optie a). Vóór
  het inloggen is er geen token, en artwork komt alleen met een
  Authorization-header binnen; GET /info draagt geen servernaam of aantallen.
  Het vlak toont daarom het merkteken op --panel, en het onderschrift alleen
  de host waar de kijker op inlogt.
-->
<div class="login">
  <div class="login__art">
    <img class="login__mark" src="/brand/pleya-mark-256.png" alt="" width="256" height="256" />
    <p class="login__host">{page.url.host}</p>
  </div>

  <div class="login__pane">
    <form class="login__box" onsubmit={submit}>
      <div class="login__brand">
        <img src="/brand/pleya-mark-64.png" alt="" width="36" height="36" />
        <span>{t('app.name')}</span>
      </div>
      <h1 class="login__title">{t('login.title')}</h1>
      <p class="login__sub">{t('login.subtitle')}</p>

      <div class="login__fields">
        <Field
          label={t('login.username')}
          bind:value={username}
          autocomplete="username"
          required
        />
        <Field
          label={t('login.password')}
          type="password"
          bind:value={password}
          autocomplete="current-password"
          required
          error={error ?? undefined}
        />
      </div>

      <!--
        De fout staat zichtbaar onder het wachtwoordveld, maar die tekst
        verschijnt zonder live-regio en een schermlezer zou hem niet horen.
        Deze regio staat er altijd en meldt dezelfde zin, zoals het oude
        foutvak deed.
      -->
      <p class="visually-hidden" role="alert">{error ?? ''}</p>

      <button class="btn btn--full login__submit" type="submit" disabled={!valid || busy}>
        {busy ? t('loading') : t('login.submit')}
      </button>

      <p class="login__help">{t('login.forgotHelp')}</p>
    </form>
  </div>
</div>

<style>
  .login {
    min-height: 100dvh;
    display: grid;
    grid-template-columns: 1fr 1fr;
  }

  .login__art {
    position: relative;
    display: grid;
    place-items: center;
    background: var(--panel);
    border-right: 1px solid var(--hairline);
  }

  /* Het merkteken heeft een eigen, ondoorzichtige grond (gen_brand_assets.py);
     afgerond leest dat als appicoon in plaats van als los vierkant. */
  .login__mark {
    width: 160px;
    height: 160px;
    border-radius: var(--radius-card);
  }

  /* Waar in 12 de servernaam staat: links onder, 40 van de rand. */
  .login__host {
    position: absolute;
    left: 40px;
    right: 40px;
    bottom: 36px;
    font-size: 22px;
    font-weight: 700;
    overflow-wrap: anywhere;
  }

  .login__pane {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 40px;
  }

  .login__box {
    width: 100%;
    max-width: 380px;
  }

  /*
   * De wordmark als merkteken plus naam, zoals de topnavigatie. Het
   * wordmark-PNG uit de northstar heeft witte letters en verdwijnt in het
   * lichte thema; tekst in --ink volgt het thema.
   */
  .login__brand {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 36px;
    margin-bottom: 28px;
    font-size: 22px;
    font-weight: 700;
    letter-spacing: -0.2px;
  }

  .login__brand img {
    border-radius: var(--radius-sm);
  }

  .login__title {
    font-size: 28px;
    font-weight: 700;
    letter-spacing: -0.01em;
  }

  .login__sub {
    margin-top: 6px;
    font-size: 14px;
    color: var(--ink-2);
  }

  /* 14 boven elk label, zoals .label in web.css. */
  .login__fields {
    display: flex;
    flex-direction: column;
    gap: 14px;
    margin-top: 14px;
  }

  .login__submit {
    margin-top: 22px;
  }

  .login__help {
    margin-top: 18px;
    font-size: 12px;
    line-height: 1.4;
    color: var(--ink-3);
  }

  @media (max-width: 899px) {
    .login {
      grid-template-columns: 1fr;
      grid-template-rows: auto 1fr;
    }

    .login__art {
      height: 260px;
      border-right: 0;
      border-bottom: 1px solid var(--hairline);
    }

    .login__mark {
      width: 112px;
      height: 112px;
    }

    .login__host {
      left: 16px;
      right: 16px;
      bottom: 16px;
    }

    .login__pane {
      align-items: flex-start;
      padding: 24px 16px 40px;
    }
  }
</style>
