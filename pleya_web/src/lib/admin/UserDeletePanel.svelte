<!--
  Verwijderen op scherm 27, met een bevestiging die om de gebruikersnaam vraagt
  (`ConfirmDialog` met `requirePhrase`). Het contract vraagt zelf geen
  bevestiging voor `DELETE /users/{id}`, dus die staat hier alleen in de UI; de
  server weigert wel de eigenaar (`auth.owner_immutable`). Het eigen account is
  hier niet te verwijderen: dat zou je eigen beheerrecht in één klik opheffen.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import Panel from '../components/Panel.svelte';
  import { t } from '../i18n';

  interface Props {
    username: string;
    /** Waarom verwijderen niet kan: de eigenaar of het eigen account. */
    blocked: 'owner' | 'self' | null;
    busy: boolean;
    open?: boolean;
    onconfirm: () => void;
  }

  let { username, blocked, busy, open = $bindable(false), onconfirm }: Props = $props();
</script>

<Panel tone="danger">
  {#snippet title()}{t('admin.users.delete.title')}{/snippet}
  <p class="help">
    {blocked === 'owner'
      ? t('admin.users.delete.owner')
      : blocked === 'self'
        ? t('admin.users.delete.self')
        : t('admin.users.delete.help', { name: username })}
  </p>
  <button
    type="button"
    class="btn btn--danger btn--sm"
    disabled={blocked !== null}
    onclick={() => (open = true)}
  >
    <AdminIcon name="trash" size={16} />{t('admin.users.delete.open')}
  </button>
</Panel>

<ConfirmDialog
  bind:open
  {busy}
  title={t('admin.users.delete.confirmTitle', { name: username })}
  message={t('admin.users.delete.confirmBody', { name: username })}
  requirePhrase={username}
  phraseLabel={t('admin.users.delete.phrase')}
  confirmLabel={t('admin.users.delete.confirm')}
  {onconfirm}
>
  {#snippet confirmIcon()}<AdminIcon name="trash" size={18} />{/snippet}
</ConfirmDialog>

<style>
  .help {
    margin: 0 0 12px;
    font-size: 13px;
    line-height: 1.45;
    color: var(--ink-3);
  }
</style>
