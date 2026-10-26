<!--
  Ondertekensleutel (31, rode kaart): roteren trekt eerst elke sessie in en
  vervangt daarna de sleutel. Daarna is ook jouw token dood; inloggen hoort
  erbij. De bevestiging eist het woord `rotate`, hetzelfde woord dat de server
  zelf toetst (`server.confirm_mismatch`). De sleutel staat nergens op het
  scherm: de server geeft hem nooit terug.
-->
<script lang="ts">
  import AdminIcon from '../../components/AdminIcon.svelte';
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';

  let { onrotate, busy }: { onrotate: () => void; busy: boolean } = $props();
</script>

<Panel tone="danger">
  {#snippet title()}{t('admin.sec.key.title')}{/snippet}
  <p class="body">{t('admin.sec.key.body')}</p>
  <button type="button" class="btn btn--danger btn--sm rotate" disabled={busy} onclick={onrotate}>
    <AdminIcon name="refresh" size={16} />{t('admin.sec.key.rotate')}
  </button>
</Panel>

<style>
  .body {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }

  .rotate {
    margin-top: 14px;
  }
</style>
