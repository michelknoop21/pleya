<!--
  Waar de geldende waarde van een instelling vandaan komt: de omgeving waarmee
  de server startte (met de naam van de variabele) of een waarde die hier is
  opgeslagen en dus de omgeving overstemt (`GET /settings`, `source`).
-->
<script lang="ts">
  import type { SettingSource } from '../../api/types';
  import { t } from '../../i18n';

  interface Props {
    source: SettingSource;
    /** De variabele die deze instelling in de omgeving heeft, of null als er geen is. */
    env: string | null;
  }

  let { source, env }: Props = $props();
</script>

<p class="src" data-source={source}>
  {#if source === 'db'}
    {t('admin.set.source.db')}
  {:else if env}
    {t('admin.set.source.env')}<span class="mono">{env}</span>
  {:else}
    {t('admin.set.source.default')}
  {/if}
</p>

<style>
  .src {
    margin: 6px 0 0;
    font-size: 12px;
    line-height: 1.4;
    color: var(--ink-3);
  }

  .mono {
    font-family: var(--font-mono);
    font-size: 11.5px;
    color: var(--ink-2);
  }
</style>
