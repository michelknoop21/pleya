<!--
  De bevestiging van een restore. Het is de zwaarste knop van beheer: de
  huidige data wordt vervangen en de server is een paar minuten weg. Daarom
  staat de zin van de server er leesbaar, en blijft de knop uit tot hij
  letterlijk is overgetypt (`requirePhrase`, hoofdlettergevoelig). De pagina
  stuurt daarna `restore_confirmation` van de back-up mee en niet wat er
  getypt werd; de server toetst hetzelfde nog eens.
-->
<script lang="ts">
  import ConfirmDialog from '../../components/ConfirmDialog.svelte';
  import type { Backup } from '../../api/types';
  import { t } from '../../i18n';
  import { formatDayClock } from '../../util/format';

  interface Props {
    backup: Backup | null;
    open?: boolean;
    busy: boolean;
    onconfirm: () => void;
  }

  let { backup, open = $bindable(false), busy, onconfirm }: Props = $props();

  const when = $derived(backup ? (formatDayClock(backup.started_at) ?? backup.started_at) : '');
  const phrase = $derived(backup?.restore_confirmation ?? '');
</script>

{#if backup && phrase}
  <ConfirmDialog
    bind:open
    {busy}
    title={t('admin.bak.restore.confirmTitle', { when })}
    message={t('admin.bak.restore.confirmBody')}
    requirePhrase={phrase}
    phraseLabel={t('admin.bak.restore.phrase')}
    confirmLabel={t('admin.bak.restore.confirm')}
    {onconfirm}
  >
    <p class="lead">{t('admin.bak.restore.lose')}</p>
    <ol class="steps">
      <li>{t('admin.bak.restore.step1')}</li>
      <li>{t('admin.bak.restore.step2')}</li>
      <li>{t('admin.bak.restore.step3')}</li>
      <li>{t('admin.bak.restore.step4')}</li>
    </ol>
    <p class="lead">{t('admin.bak.restore.sentence')}</p>
    <p class="phrase" data-restore-phrase>{phrase}</p>
  </ConfirmDialog>
{/if}

<style>
  .lead {
    margin: 0 0 6px;
    font-size: 13px;
    font-weight: 600;
  }

  .steps {
    margin: 0 0 12px;
    padding-left: 20px;
    list-style: decimal;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }

  .phrase {
    margin: 0 0 4px;
    padding: 8px 10px;
    border-radius: 8px;
    background: var(--panel-2, rgb(255 255 255 / 6%));
    font-family: var(--font-mono);
    font-size: 12.5px;
    line-height: 1.45;
    overflow-wrap: anywhere;
    user-select: all;
  }
</style>
