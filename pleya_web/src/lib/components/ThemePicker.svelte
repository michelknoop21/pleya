<!--
  Dezelfde vier standen als de app: OLED, dark, light en system. Op web is
  dark de standaard (stores/theme.svelte.ts zegt waarom). Een select en geen eigen menu: een browser levert er al een die
  met toetsenbord en schermlezer werkt.
-->
<script lang="ts">
  import { THEME_MODES, isThemeMode, theme } from '../stores/theme.svelte';
  import { t } from '../i18n';

  /** Id van de kop die dit veld benoemt; zonder valt hij terug op een eigen label. */
  let { labelledby }: { labelledby?: string } = $props();

  const labels: Record<(typeof THEME_MODES)[number], string> = {
    oled: t('theme.oled'),
    dark: t('theme.dark'),
    light: t('theme.light'),
    system: t('theme.system')
  };
</script>

{#snippet control()}
  <select
    class="picker__select"
    aria-labelledby={labelledby}
    value={theme.mode}
    onchange={(event) => {
      const value = event.currentTarget.value;
      if (isThemeMode(value)) theme.set(value);
    }}
  >
    {#each THEME_MODES as mode (mode)}
      <option value={mode}>{labels[mode]}</option>
    {/each}
  </select>
{/snippet}

<!-- Met `labelledby` is de kop van het paneel de naam; een tweede verborgen
     label zou de schermlezer dezelfde woorden twee keer laten zeggen. -->
{#if labelledby}
  {@render control()}
{:else}
  <label class="picker">
    <span class="visually-hidden">{t('settings.theme')}</span>
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
