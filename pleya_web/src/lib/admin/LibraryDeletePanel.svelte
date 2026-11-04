<!--
  Verwijderen op scherm 22, met de bevestiging van scherm 23. De knop opent
  ConfirmDialog met `requirePhrase` op de titel: de verwijderknop blijft
  uitgeschakeld tot de naam letterlijk getypt is (K rij 16). De server toetst
  hetzelfde (`confirm` moet de titel zijn), dus `onconfirm` stuurt de titel
  mee en niet wat er getypt werd.

  De northstar noemt het aantal gebruikers met kijkstatus en de opslaggrootte.
  Het contract levert die niet per bibliotheek; de tekst noemt alleen wat de
  server wel weet, het aantal titels.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import Panel from '../components/Panel.svelte';
  import type { Library } from '../api/types';
  import { t } from '../i18n';
  import { countLabel } from './overview';

  interface Props {
    library: Library;
    busy: boolean;
    open?: boolean;
    onconfirm: () => void;
  }

  let { library, busy, open = $bindable(false), onconfirm }: Props = $props();
</script>

<Panel tone="danger">
  {#snippet title()}{t('admin.lib.delete.title')}{/snippet}
  <p class="help">{t('admin.lib.delete.help')}</p>
  <button type="button" class="btn btn--danger btn--sm" onclick={() => (open = true)}>
    <AdminIcon name="trash" size={16} />{t('admin.lib.delete.open')}
  </button>
</Panel>

<ConfirmDialog
  bind:open
  {busy}
  title={t('admin.lib.delete.confirmTitle', { name: library.title })}
  message={t('admin.lib.delete.confirmBody', {
    titles: countLabel('admin.lib.titles', library.item_count)
  })}
  requirePhrase={library.title}
  phraseLabel={t('admin.lib.delete.phrase')}
  confirmLabel={t('admin.lib.delete.confirm')}
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
