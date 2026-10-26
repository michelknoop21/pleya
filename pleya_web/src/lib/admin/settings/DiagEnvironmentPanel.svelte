<!--
  Omgeving (32, rechts): de `PLEYA_SERVER_*`-variabelen zoals de server ze
  toont (`GET /server/environment`), alleen lezen. De server laat een variabele
  met een geheimnaam weg en maskeert de DSN; `maskEntry` is een tweede slot
  daarachter. Wat gemaskeerd is draagt het label "gemaskeerd", zodat niemand een
  afgeschermde DSN voor de echte waarde houdt.
-->
<script lang="ts">
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';
  import { maskEntry, type EnvironmentEntry } from './diagnostics';

  let { entries }: { entries: EnvironmentEntry[] | null } = $props();

  const shown = $derived((entries ?? []).map(maskEntry));
</script>

<Panel>
  {#snippet title()}{t('admin.diag.env.title')}{/snippet}
  {#snippet actions()}<span class="aside">{t('admin.diag.env.aside')}</span>{/snippet}
  {#if entries === null}
    <p class="note">{t('admin.diag.env.unreadable')}</p>
  {:else if shown.length === 0}
    <p class="note">{t('admin.diag.env.empty')}</p>
  {:else}
    <dl class="env">
      {#each shown as entry (entry.key)}
        <dt class="mono">{entry.key}</dt>
        <dd class="mono">
          {entry.value}{#if entry.redacted}<span class="tag">{t('admin.diag.env.masked')}</span>{/if}
        </dd>
      {/each}
    </dl>
  {/if}
</Panel>

<style>
  .aside {
    font-size: 12.5px;
    color: var(--ink-3);
  }

  /* Een naam als PLEYA_SERVER_TRANSCODE_MAX_SESSIONS past naast zijn waarde pas op
     een breed scherm; daaronder staat de waarde onder de naam. */
  .env {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    gap: 2px;
    margin: 0;
    font-size: 12.5px;
  }

  .env dt {
    color: var(--ink-3);
    overflow-wrap: anywhere;
  }

  .env dd {
    margin: 0;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .tag {
    margin-left: 8px;
    padding: 1px 7px;
    border-radius: 6px;
    background: var(--fill);
    color: var(--ink-2);
    font-family: var(--font-sans);
    font-size: 11.5px;
  }

  .note {
    margin: 0;
    font-size: 13px;
    color: var(--ink-3);
  }

  .env dd {
    margin-bottom: 8px;
  }

  @media (min-width: 1500px) {
    .env {
      grid-template-columns: minmax(0, 1.3fr) minmax(0, 1fr);
      gap: 8px 16px;
    }

    .env dd {
      margin-bottom: 0;
    }
  }
</style>
