<!--
  Een gebruiker toevoegen (`POST /users`). De northstar tekent hier geen eigen
  scherm voor; dit is scherm 27 met alleen wat bij het aanmaken kan: naam,
  wachtwoord en rol. De eigenaar is niet te kiezen (er is er precies één, uit
  setup). Rechten per bibliotheek kent het aanmaken niet: na het opslaan gaat
  de pagina naar de gebruiker zelf, waar ze te zetten zijn.

  Het wachtwoord gaat alleen in de aanvraag, nooit in de URL, en het veld
  vraagt de browser niets te onthouden (`autocomplete="new-password"`).
-->
<script lang="ts">
  import { goto } from '$app/navigation';

  import { adminUsersApi } from '../api/adminUsers';
  import Choice, { type ChoiceOption } from '../components/Choice.svelte';
  import Field from '../components/Field.svelte';
  import Panel from '../components/Panel.svelte';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import AdminPageHead from './AdminPageHead.svelte';
  import UserProblemAlert from './UserProblemAlert.svelte';
  import { userProblem, type UserProblem } from './userErrors';
  import {
    ASSIGNABLE_ROLES,
    PASSWORD_MIN,
    passwordProblem,
    roleHint,
    roleLabel,
    usernameProblem
  } from './users';

  const LIST = '/admin/users';
  const uid = $props.id();
  const formId = `${uid}-form`;

  let username = $state('');
  let password = $state('');
  let role = $state<string>('member');
  let submitted = $state(false);
  let saving = $state(false);
  let problem = $state<UserProblem | null>(null);

  const nameKey = $derived(usernameProblem(username));
  const passwordKey = $derived(passwordProblem(password));

  const roleOptions: ChoiceOption[] = ASSIGNABLE_ROLES.map((r) => ({
    value: r,
    label: roleLabel(r),
    description: roleHint(r)
  }));

  async function save(): Promise<void> {
    submitted = true;
    if (saving || nameKey || passwordKey) return;
    problem = null;
    saving = true;
    const name = username.trim();
    try {
      const created = await adminUsersApi(session.client).createUser({
        username: name,
        password,
        role: role as (typeof ASSIGNABLE_ROLES)[number]
      });
      password = '';
      await goto(`${LIST}/${created.id}?added=${encodeURIComponent(created.username)}`);
    } catch (err) {
      problem = userProblem(err, name);
    } finally {
      saving = false;
    }
  }
</script>

<AdminPageHead
  title={t('admin.users.action.add')}
  crumbs={[
    { label: t('admin.title'), href: '/admin' },
    { label: t('admin.nav.users'), href: LIST },
    { label: t('admin.users.new') }
  ]}
/>

{#if problem}
  <div class="msg">
    <UserProblemAlert {problem} onretry={() => void save()} />
  </div>
{/if}

<form class="cols" id={formId} onsubmit={(e) => {
    e.preventDefault();
    void save();
  }} novalidate>
  <Panel>
    {#snippet title()}{t('admin.users.account.title')}{/snippet}
    <div class="form">
      <Field
        label={t('admin.users.form.username')}
        bind:value={username}
        autocomplete="off"
        required
        error={submitted && nameKey ? t(nameKey) : undefined}
      />
      <Field
        label={t('admin.users.form.password')}
        type="password"
        bind:value={password}
        autocomplete="new-password"
        required
        hint={t('admin.users.form.passwordHint', { min: PASSWORD_MIN })}
        error={submitted && passwordKey ? t(passwordKey) : undefined}
      />
    </div>
  </Panel>
  <Panel>
    {#snippet title()}{t('admin.users.rolePanel.title')}{/snippet}
    <Choice legend={t('admin.users.rolePanel.title')} hideLegend options={roleOptions} bind:value={role} />
  </Panel>
  <div class="foot">
    <a class="btn btn--ghost" href={LIST}>{t('dialog.cancel')}</a>
    <button
      type="submit"
      class="btn"
      disabled={saving}
      aria-busy={saving ? 'true' : undefined}
    >
      {t('admin.users.action.create')}
    </button>
  </div>
</form>

<style>
  .msg {
    margin-bottom: 14px;
  }

  .cols {
    display: grid;
    gap: 14px;
    max-width: 760px;
  }

  .form {
    display: grid;
    gap: 16px;
    max-width: 560px;
  }

  .foot {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 10px;
    margin-top: 6px;
  }

  @media (max-width: 899px) {
    .foot .btn {
      flex: 1 1 auto;
    }
  }
</style>
