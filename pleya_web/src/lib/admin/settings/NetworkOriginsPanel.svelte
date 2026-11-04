<!--
  Herkomst en CORS (30): `web_origin`, het adres van de webclient die bij deze
  server hoort, en `cors_origins`, de origins die de API cross-origin mogen
  aanroepen. De northstar tekent dit paneel niet, maar beide zijn instellingen
  van `PATCH /settings` en kunnen jezelf buitensluiten, dus ze horen op dit
  scherm met een duidelijke waarschuwing.
-->
<script lang="ts">
  import type { Settings } from '../../api/types';
  import Alert from '../../components/Alert.svelte';
  import Field from '../../components/Field.svelte';
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';
  import { EXAMPLE_ADDRESS, type NetworkDraft, type NetworkErrors } from './network';
  import SettingSourceHint from './SettingSourceHint.svelte';
  import { SETTING_ENV } from './settings';

  interface Props {
    settings: Settings;
    draft: NetworkDraft;
    errors: NetworkErrors;
  }

  let { settings, draft = $bindable(), errors }: Props = $props();
</script>

<Panel>
  {#snippet title()}{t('admin.net.origins.title')}{/snippet}
  <div class="stack">
    <Alert tone="warn" live={false}>{t('admin.net.origins.warn')}</Alert>
    <div>
      <Field
        label={t('admin.set.field.web_origin')}
        type="url"
        bind:value={draft.webOrigin}
        error={errors.webOrigin}
        hint={t('admin.net.origins.webHint')}
        placeholder={EXAMPLE_ADDRESS}
        autocomplete="off"
      />
      <SettingSourceHint source={settings.web_origin.source} env={SETTING_ENV.web_origin} />
    </div>
    <div>
      <Field
        label={t('admin.set.field.cors_origins')}
        error={errors.cors}
        hint={t('admin.net.origins.corsHint')}
      >
        {#snippet children(control)}
          <textarea
            id={control.id}
            rows="3"
            spellcheck="false"
            autocomplete="off"
            autocapitalize="off"
            aria-invalid={control.invalid ? 'true' : undefined}
            aria-describedby={control.describedby}
            bind:value={draft.cors}
          ></textarea>
        {/snippet}
      </Field>
      <SettingSourceHint source={settings.cors_origins.source} env={SETTING_ENV.cors_origins} />
    </div>
  </div>
</Panel>

<style>
  .stack {
    display: grid;
    gap: 18px;
  }
</style>
