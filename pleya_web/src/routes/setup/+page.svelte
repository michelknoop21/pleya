<script lang="ts">
  import { goto } from '$app/navigation';
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

<form class="auth" onsubmit={submit}>
  <img class="auth__mark" src="/brand/pleya-mark-256.png" alt="" width="96" height="96" />
  <h1 class="t-headline">{t('setup.title')}</h1>
  <p class="t-body auth__intro">{t('setup.intro')}</p>

  {#if error}
    <p class="auth__error t-body" role="alert">{error}</p>
  {/if}

  <label class="auth__field">
    <span class="t-small">{t('setup.code')}</span>
    <input
      class="field"
      bind:value={setupCode}
      autocomplete="one-time-code"
      required
      spellcheck="false"
    />
  </label>

  <label class="auth__field">
    <span class="t-small">{t('setup.username')}</span>
    <input class="field" bind:value={username} autocomplete="username" required />
  </label>

  <label class="auth__field">
    <span class="t-small">{t('setup.password')}</span>
    <input
      class="field"
      type="password"
      bind:value={password}
      autocomplete="new-password"
      minlength="8"
      required
      aria-describedby="password-hint"
    />
    <span class="t-small" id="password-hint">{t('setup.passwordHint')}</span>
  </label>

  <button class="btn" type="submit" disabled={!valid || busy}>
    {busy ? t('loading') : t('setup.submit')}
  </button>
</form>

<style>
  .auth {
    display: flex;
    flex-direction: column;
    gap: var(--space);
    width: min(100%, 400px);
  }

  .auth__mark {
    align-self: center;
  }

  .auth__intro {
    color: var(--text-muted);
  }

  .auth__error {
    padding: var(--space);
    border-radius: var(--radius-sm);
    background: color-mix(in srgb, var(--error) 18%, transparent);
    border: 1px solid color-mix(in srgb, var(--error) 45%, transparent);
  }

  .auth__field {
    display: flex;
    flex-direction: column;
    gap: var(--space-quarter);
  }
</style>
