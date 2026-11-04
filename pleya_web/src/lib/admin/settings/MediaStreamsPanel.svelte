<!--
  Afspelen in de browser (28, linksboven): hoeveel streamsessies een gebruiker
  tegelijk mag hebben en hoe lang een sessie of een streamtoken leeft. Dat zijn
  de drie sleutels `max_stream_sessions`, `stream_session_ttl` en
  `stream_token_ttl` van `PATCH /settings`. Een draft wordt bovenin de pagina
  bewaard; dit paneel toont en wijzigt hem alleen.
-->
<script lang="ts">
  import type { Settings } from '../../api/types';
  import Panel from '../../components/Panel.svelte';
  import Select from '../../components/Select.svelte';
  import { t } from '../../i18n';
  import { maxStreamOptions, type MediaDraft } from './media';
  import SettingSourceHint from './SettingSourceHint.svelte';
  import { durationOptions, SETTING_ENV, settingSeconds } from './settings';

  interface Props {
    settings: Settings;
    draft: MediaDraft;
  }

  let { settings, draft = $bindable() }: Props = $props();

  const sessionNow = $derived(settingSeconds(settings, 'stream_session_ttl') ?? 0);
  const tokenNow = $derived(settingSeconds(settings, 'stream_token_ttl') ?? 0);
</script>

<Panel>
  {#snippet title()}{t('admin.media.streams.title')}{/snippet}
  <div class="stack">
    <div>
      <Select
        label={t('admin.media.streams.max')}
        options={maxStreamOptions(settings.max_stream_sessions.value)}
        bind:value={draft.maxStreams}
      />
      <p class="note">{t('admin.media.streams.maxHint')}</p>
      <SettingSourceHint source={settings.max_stream_sessions.source} env={SETTING_ENV.max_stream_sessions} />
    </div>
    <div>
      <Select
        label={t('admin.media.streams.ttl')}
        options={durationOptions('stream_session_ttl', sessionNow)}
        bind:value={draft.sessionTtl}
      />
      <p class="note">{t('admin.media.streams.ttlHint')}</p>
      <SettingSourceHint source={settings.stream_session_ttl.source} env={SETTING_ENV.stream_session_ttl} />
    </div>
    <div>
      <Select
        label={t('admin.media.streams.token')}
        options={durationOptions('stream_token_ttl', tokenNow)}
        bind:value={draft.tokenTtl}
      />
      <p class="note">{t('admin.media.streams.tokenHint')}</p>
      <SettingSourceHint source={settings.stream_token_ttl.source} env={SETTING_ENV.stream_token_ttl} />
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
