<!--
  Downloads naar apps (28): alleen of de server ze aanbiedt
  (`capabilities.downloads`). Wie mag downloaden volgt het bibliotheekrecht
  Downloaden (scherm 27); er is geen aparte serverinstelling voor, en voor de
  kwaliteit van een omgezette download evenmin. Daarom staat hier geen keuzelijst.
-->
<script lang="ts">
  import Panel from '../../components/Panel.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { t } from '../../i18n';

  let { enabled }: { enabled: boolean } = $props();
</script>

<Panel>
  {#snippet title()}{t('admin.media.downloads.title')}{/snippet}
  {#snippet actions()}
    <StatusPill
      variant="dot"
      tone={enabled ? 'ok' : 'idle'}
      label={enabled ? t('admin.set.on') : t('admin.set.off')}
    />
  {/snippet}
  <p class="body">{t('admin.media.downloads.body')}</p>
</Panel>

<style>
  .body {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
