<!--
  Het blok "Terugzetten" van scherm 35: wat een restore doet, uitgeschreven vóór
  iemand op een knop drukt. De knop zelf staat per rij in de lijst; dit paneel
  heeft er geen, want de keuze van de back-up is het eerste wat telt.
-->
<script lang="ts">
  import Alert from '../../components/Alert.svelte';
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';
</script>

<Panel tone="warn">
  {#snippet title()}{t('admin.bak.restore.title')}{/snippet}
  <p class="body">{t('admin.bak.restore.body')}</p>
  <Alert tone="info" live={false}>{t('admin.bak.restore.older')}</Alert>
</Panel>

<style>
  .body {
    margin: 0 0 14px;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
