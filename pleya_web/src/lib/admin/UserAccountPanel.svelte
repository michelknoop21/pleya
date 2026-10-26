<!--
  Het paneel Account van scherm 27: de gebruikersnaam (alleen te lezen, het
  contract kent geen hernoemen) en Wachtwoord opnieuw instellen. Een beheerder
  kiest een nieuw wachtwoord en geeft het door; de server toont het huidige
  nooit. De eigenaar zet zijn wachtwoord alleen zelf (`auth.owner_immutable`
  voor een ander), dus voor een andere beheerder dan hij is de knop uit.

  Het nieuwe wachtwoord gaat alleen in de aanvraag; het veld wordt na het
  versturen leeggemaakt en vraagt de browser niets te onthouden.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import Field from '../components/Field.svelte';
  import Panel from '../components/Panel.svelte';
  import { t } from '../i18n';
  import { PASSWORD_MIN, passwordProblem } from './users';

  interface Props {
    username: string;
    /** Mag de beheerder het wachtwoord van deze gebruiker zetten? */
    canReset: boolean;
    busy: boolean;
    onreset: (password: string) => Promise<boolean>;
  }

  let { username, canReset, busy, onreset }: Props = $props();

  let open = $state(false);
  let password = $state('');
  let submitted = $state(false);

  const problem = $derived(passwordProblem(password));

  async function submit(event: SubmitEvent): Promise<void> {
    event.preventDefault();
    submitted = true;
    if (problem || busy) return;
    const ok = await onreset(password);
    password = '';
    if (ok) {
      open = false;
      submitted = false;
    }
  }

  function cancel(): void {
    open = false;
    password = '';
    submitted = false;
  }
</script>

<Panel>
  {#snippet title()}{t('admin.users.account.title')}{/snippet}
  <div class="body">
    <Field label={t('admin.users.form.username')} value={username} disabled autocomplete="off" />
    {#if open}
      <form class="reset" onsubmit={(e) => void submit(e)} novalidate>
        <Field
          label={t('admin.users.account.newPassword')}
          type="password"
          bind:value={password}
          autocomplete="new-password"
          required
          hint={t('admin.users.form.passwordHint', { min: PASSWORD_MIN })}
          error={submitted && problem ? t(problem) : undefined}
        />
        <div class="acts">
          <button type="submit" class="btn btn--sm" disabled={busy} aria-busy={busy ? 'true' : undefined}>
            {t('admin.users.account.setPassword')}
          </button>
          <button type="button" class="btn btn--ghost btn--sm" onclick={cancel}>
            {t('dialog.cancel')}
          </button>
        </div>
      </form>
    {:else}
      <div>
        <button
          type="button"
          class="btn btn--secondary btn--sm"
          disabled={!canReset}
          onclick={() => (open = true)}
        >
          <AdminIcon name="gear" size={16} />{t('admin.users.account.reset')}
        </button>
      </div>
    {/if}
    <p class="help">
      {canReset ? t('admin.users.account.resetHelp') : t('admin.users.account.ownerOnly')}
    </p>
  </div>
</Panel>

<style>
  .body {
    display: grid;
    gap: 14px;
  }

  .reset {
    display: grid;
    gap: 12px;
  }

  .acts {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }

  .help {
    margin: 0;
    font-size: 13px;
    line-height: 1.45;
    color: var(--ink-3);
  }
</style>
