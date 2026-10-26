<!--
  Capabilities (32): wat de server via `GET /info` adverteert. Een vlag die
  aanstaat is gevuld, een die uitstaat is gedimd; de naam is de sleutel uit het
  contract. Er is geen instelling om een vlag aan te zetten: de server zet hem
  zelf aan wanneer hij het gedrag werkelijk levert.
-->
<script lang="ts">
  import type { Info } from '../../api/types';
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';
  import { capabilityFlags } from './diagnostics';

  let { info }: { info: Info } = $props();

  const flags = $derived(capabilityFlags(info));
</script>

<Panel>
  {#snippet title()}{t('admin.diag.caps.title')}{/snippet}
  {#snippet actions()}<span class="aside">{t('admin.diag.caps.aside')}</span>{/snippet}
  <ul class="flags">
    {#each flags as flag (flag.name)}
      <li class="flag" class:flag--on={flag.on} data-flag={flag.name} data-on={flag.on}>
        {flag.name}<span class="visually-hidden"> {flag.on ? t('admin.set.on') : t('admin.set.off')}</span>
      </li>
    {/each}
  </ul>
  <p class="note">{t('admin.diag.caps.note')}</p>
</Panel>

<style>
  .aside {
    font-size: 12.5px;
    color: var(--ink-3);
  }

  .flags {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .flag {
    padding: 7px 14px;
    border-radius: var(--radius-pill);
    background: var(--fill);
    color: var(--ink-3);
    font-size: 13.5px;
    font-weight: 600;
  }

  .flag--on {
    background: var(--ink);
    color: var(--bg);
  }

  .note {
    margin: 12px 0 0;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
