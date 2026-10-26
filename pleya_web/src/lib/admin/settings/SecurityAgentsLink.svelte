<!--
  De ingang van Beveiliging (31) naar Agents en API-tokens (34). De northstar
  tekent geen eigen ingang, maar 34 hangt in zijn kruimelpad onder Beveiliging
  en heeft anders geen zichtbare weg. De zijbalk en de mobiele index blijven
  tien secties (`sections.ts`): 34 is een scherm binnen Beveiliging.
-->
<script lang="ts">
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';
</script>

<Panel>
  {#snippet title()}{t('admin.tok.entry.title')}{/snippet}
  <p class="body">{t('admin.tok.entry.body')}</p>
  <a class="btn btn--secondary btn--sm" href="/admin/security/agents">{t('admin.tok.entry.open')}</a>
</Panel>

<style>
  .body {
    margin: 0 0 12px;
    font-size: 13.5px;
    line-height: 1.5;
    color: var(--ink-2);
  }
</style>
