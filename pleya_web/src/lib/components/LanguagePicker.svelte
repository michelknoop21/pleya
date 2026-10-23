<!--
  De taalkeuze van Mijn Pleya, in dezelfde vorm als ThemePicker: een native
  select, want een browser levert er al een die met toetsenbord en schermlezer
  werkt. De opties staan in hun eigen taal en worden niet vertaald: wie per
  ongeluk de verkeerde taal koos, vindt zijn eigen taal dan nog terug.

  Kiezen herlaadt de pagina (changeLocale), dus er is geen aria-live nodig: de
  nieuwe pagina is de bevestiging. `reload` is injecteerbaar voor de tests.
-->
<script lang="ts">
  import { LOCALES, changeLocale, locale, t, type Locale } from '../i18n';

  /** `labelledby`: id van de kop die dit veld benoemt; zonder valt hij terug op een eigen label. */
  let { reload, labelledby }: { reload?: () => void; labelledby?: string } = $props();

  // Eigen naam per taal, bewust niet via t().
  const NAMES: Record<Locale, string> = { en: 'English', nl: 'Nederlands' };

  function isLocale(value: string): value is Locale {
    return (LOCALES as readonly string[]).includes(value);
  }
</script>

{#snippet control()}
  <select
    class="picker__select"
    aria-labelledby={labelledby}
    value={locale()}
    onchange={(event) => {
      const value = event.currentTarget.value;
      if (isLocale(value)) changeLocale(value, reload);
    }}
  >
    {#each LOCALES as code (code)}
      <option value={code} lang={code}>{NAMES[code]}</option>
    {/each}
  </select>
{/snippet}

<!-- Met `labelledby` is de kop van het paneel de naam; een tweede verborgen
     label zou de schermlezer dezelfde woorden twee keer laten zeggen. -->
{#if labelledby}
  {@render control()}
{:else}
  <label class="picker">
    <span class="visually-hidden">{t('settings.language')}</span>
    {@render control()}
  </label>
{/if}

<style>
  .picker__select {
    min-height: var(--touch-target);
    padding: var(--space-half) var(--space);
    border-radius: var(--radius-md);
    border: 1px solid var(--hairline);
    background: var(--inset-bg);
    color: var(--text);
  }
</style>
