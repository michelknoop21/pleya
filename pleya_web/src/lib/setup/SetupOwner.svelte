<script lang="ts">
  import Alert from '#lib/components/Alert.svelte';
  import Field from '#lib/components/Field.svelte';
  import { session } from '#lib/stores/session.svelte.js';
  import { ApiError, describeError } from '#lib/api/errors.js';
  import { deviceFields } from '#lib/auth/device.js';
  import { t } from '#lib/i18n/index.js';

  let serverName = $state('');
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
      const credentials = {setup_code: setupCode.trim(), username: username.trim(), password};
      setupCode = ''; password = '';
      await session.client.setup({
        ...credentials,
        ...(session.info?.server.setup_accepts_name && serverName.trim() ? {server_name: serverName.trim()} : {}),
        ...deviceFields(session.capabilities)
      });
      await session.afterAuth();

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

  <form class="owner" onsubmit={submit}>
    <h1 class="setup__title">{t('setup.title')}</h1>
    <p class="setup__sub">{t('setup.intro')}</p>

    <div class="setup__fields">
      {#if session.info?.server.setup_accepts_name}
        <Field label={t('setup.serverName')} bind:value={serverName} maxlength={64} />
      {/if}
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


<style>
.setup__fields{display:grid;gap:14px;margin-top:20px}.setup__error{margin-top:20px}.setup__foot{display:flex;justify-content:flex-end;margin-top:28px}h1{font-size:28px;letter-spacing:-.01em}p{color:var(--ink-2);line-height:1.45;margin-top:8px}@media(max-width:899px){.setup__submit{width:100%}}
</style>
