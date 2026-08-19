<!--
  Dezelfde vier standen als de app: OLED, dark, light en system, met OLED als
  standaard. Een select en geen eigen menu: een browser levert er al een die
  met toetsenbord en schermlezer werkt.
-->
<script lang="ts">
  import { THEME_MODES, isThemeMode, theme } from '../stores/theme.svelte';
  import { t } from '../i18n';

  const labels: Record<(typeof THEME_MODES)[number], string> = {
    oled: t('theme.oled'),
    dark: t('theme.dark'),
    light: t('theme.light'),
    system: t('theme.system')
  };
</script>

<label class="picker">
  <span class="visually-hidden">{t('settings.theme')}</span>
  <select
    class="picker__select"
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
</label>

<style>
  .picker__select {
    min-height: var(--touch-target);
    padding: var(--space-half) var(--space);
    border-radius: var(--radius-md);
    border: 1px solid var(--outline);
    background: var(--surface);
    color: var(--text);
  }
</style>
