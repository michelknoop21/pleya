<!--
  Bibliotheek toevoegen, Geavanceerd: het scaninterval en scannen bij het
  opstarten, de twee velden die `CreateLibraryRequest` naast naam, soort en
  mappen kent. Een gewone <details>: de browser levert de toets, de rol en de
  open-staat.

  Uit het doelbeeld niet gebouwd, omdat er geen veld of route voor is:
  bestandsbewaking, de metadatabron per bibliotheek en wie mag kijken.
-->
<script lang="ts">
  import Panel from '../components/Panel.svelte';
  import Select from '../components/Select.svelte';
  import Toggle from '../components/Toggle.svelte';
  import { t } from '../i18n';
  import { intervalOptions, type LibraryForm } from './libraries';

  let { form = $bindable() }: { form: LibraryForm } = $props();
</script>

<Panel>
  <details open>
    <summary>{t('admin.lib.step.advanced')}</summary>
    <div class="rows">
      <div>
        <Select
          label={t('admin.lib.form.interval')}
          options={intervalOptions(form.interval)}
          bind:value={form.interval}
        />
        <p class="help">{t('admin.lib.form.intervalHelp')}</p>
      </div>
      <Toggle
        label={t('admin.lib.form.scanOnStart')}
        description={t('admin.lib.form.scanOnStartHelp')}
        bind:checked={form.scanOnStart}
      />
    </div>
  </details>
</Panel>

<style>
  summary {
    min-height: 32px;
    font-size: 16px;
    font-weight: 600;
    line-height: 32px;
    letter-spacing: -0.01em;
    color: var(--ink);
    cursor: pointer;
  }

  summary:focus-visible {
    outline: var(--ring) solid var(--ink);
    outline-offset: 3px;
    border-radius: var(--radius-sm, 6px);
  }

  .rows {
    display: grid;
    gap: 16px;
    max-width: 560px;
    margin-top: 14px;
  }

  .help {
    margin: 6px 0 0;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
