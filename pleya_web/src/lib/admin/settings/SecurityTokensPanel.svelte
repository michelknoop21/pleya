<!--
  Tokens (31, links): hoe lang een toegangstoken geldt en hoe lang iemand
  ingelogd blijft (de levensduur van het vernieuwingstoken). Beide zijn
  instellingen en gelden vanaf het eerstvolgende token, zonder herstart.
-->
<script lang="ts">
  import type { Settings } from '../../api/types';
  import Panel from '../../components/Panel.svelte';
  import Select from '../../components/Select.svelte';
  import { t } from '../../i18n';
  import type { SecurityDraft } from './security';
  import SettingSourceHint from './SettingSourceHint.svelte';
  import { durationOptions, SETTING_ENV, settingSeconds } from './settings';

  interface Props {
    settings: Settings;
    draft: SecurityDraft;
  }

  let { settings, draft = $bindable() }: Props = $props();
</script>

<Panel>
  {#snippet title()}{t('admin.sec.tokens.title')}{/snippet}
  <div class="stack">
    <div>
      <Select
        label={t('admin.sec.tokens.access')}
        options={durationOptions('access_token_ttl', settingSeconds(settings, 'access_token_ttl') ?? 0)}
        bind:value={draft.access}
      />
      <SettingSourceHint source={settings.access_token_ttl.source} env={SETTING_ENV.access_token_ttl} />
    </div>
    <div>
      <Select
        label={t('admin.sec.tokens.refresh')}
        options={durationOptions('refresh_token_ttl', settingSeconds(settings, 'refresh_token_ttl') ?? 0)}
        bind:value={draft.refresh}
      />
      <p class="note">{t('admin.sec.tokens.hint')}</p>
      <SettingSourceHint source={settings.refresh_token_ttl.source} env={SETTING_ENV.refresh_token_ttl} />
    </div>
  </div>
</Panel>

<style>
  .stack {
    display: grid;
    gap: 18px;
  }

  .note {
    margin: 6px 0 0;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
