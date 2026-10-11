<script lang="ts">
  import { goto } from '$app/navigation';
  import Alert from '$lib/components/Alert.svelte';
  import Field from '$lib/components/Field.svelte';
  import { session } from '$lib/stores/session.svelte';
  import { ApiError, describeError } from '$lib/api/errors';
  import { t } from '$lib/i18n';

  let setupCode = $state('');
  let username = $state('');
  let password = $state('');
  let busy = $state(false);
  let error = $state<string | null>(null);

  const valid = $derived(
    setupCode.trim().length > 0 && username.trim().length > 0 && password.length >= 8
  );

  async function submit(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    if (!valid || busy) return;
    busy = true;
    error = null;
    try {
      await session.client.setup({
        setup_code: setupCode.trim(),
        username: username.trim(),
        password
      });
      await session.afterAuth();
      await goto('/', { replaceState: true });
    } catch (err) {
      if (err instanceof ApiError && err.code === 'auth.rate_limited') {
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

<svelte:head><title>{t('setup.title')} · {t('app.name')}</title></svelte:head>

<!--
  Het formulier van stap 1 uit beeld 40, in een kolom van 620 (DESIGN.md
  hoofdstuk 3). De stappenbalk, de servernaam en het opslag- en
  bibliotheekwerk horen bij S11; tot dan is setup één formulier.
-->
<div class="setup">
  <form class="setup__box" onsubmit={submit}>
    <div class="setup__brand">
      <img src="/brand/pleya-mark-64.png" alt="" width="36" height="36" />
      <span>{t('app.name')}</span>
    </div>
    <h1 class="setup__title">{t('setup.title')}</h1>
    <p class="setup__sub">{t('setup.intro')}</p>

    <div class="setup__fields">
      <!-- Eigen invoer in Field: de code wordt letterlijk overgetypt, dus geen
           spellingcontrole, en de browser mag hem als eenmalige code invullen. -->
      <Field label={t('setup.code')} mono required>
        {#snippet children(control)}
          <input
            id={control.id}
            aria-describedby={control.describedby}
            bind:value={setupCode}
            autocomplete="one-time-code"
            spellcheck="false"
            required
          />
        {/snippet}
      </Field>
      <Field label={t('setup.username')} bind:value={username} autocomplete="username" required />
      <Field
        label={t('setup.password')}
        type="password"
        bind:value={password}
        autocomplete="new-password"
        hint={t('setup.passwordHint')}
        required
      />
    </div>

    {#if error}
      <div class="setup__error">
        <Alert tone="err">{error}</Alert>
      </div>
    {/if}

    <div class="setup__foot">
      <button class="btn setup__submit" type="submit" disabled={!valid || busy}>
        {busy ? t('loading') : t('setup.submit')}
      </button>
    </div>
  </form>
</div>

<style>
  .setup {
    display: flex;
    align-items: flex-start;
    justify-content: center;
    padding: 60px 24px;
  }

  .setup__box {
    width: 100%;
    max-width: 620px;
  }

  /* Merkteken plus naam, om dezelfde reden als op het inlogscherm. */
  .setup__brand {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 36px;
    margin-bottom: 26px;
    font-size: 22px;
    font-weight: 700;
    letter-spacing: -0.2px;
  }

  .setup__brand img {
    border-radius: var(--radius-sm);
  }

  .setup__title {
    font-size: 28px;
    font-weight: 700;
    letter-spacing: -0.01em;
  }

  .setup__sub {
    margin-top: 6px;
    font-size: 15px;
    line-height: 1.45;
    color: var(--ink-2);
  }

  .setup__fields {
    display: flex;
    flex-direction: column;
    gap: 14px;
    margin-top: 14px;
  }

  .setup__error {
    margin-top: 22px;
  }

  .setup__foot {
    display: flex;
    justify-content: flex-end;
    margin-top: 28px;
  }

  @media (max-width: 899px) {
    .setup {
      padding: 24px 16px 40px;
    }

    /* Onder 900 vol breed (DESIGN.md hoofdstuk 3, "Setup"). */
    .setup__submit {
      width: 100%;
    }
  }
</style>
