<!--
  Identiteit (30, links): servernaam, server-id en publiek adres. De naam en het
  adres zijn instellingen (`server_name`, `public_url`); het id verandert nooit
  en is alleen te kopiëren. Een geheim staat hier nergens: een publiek adres met
  inloggegevens weigert de server en deze pagina vooraf.
-->
<script lang="ts">
  import type { Settings } from '../../api/types';
  import Field from '../../components/Field.svelte';
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';
  import { EXAMPLE_ADDRESS, type NetworkDraft, type NetworkErrors } from './network';
  import SettingSourceHint from './SettingSourceHint.svelte';
  import { SETTING_ENV } from './settings';

  interface Props {
    settings: Settings;
    serverId: string;
    draft: NetworkDraft;
    errors: NetworkErrors;
  }

  let { settings, serverId, draft = $bindable(), errors }: Props = $props();

  let copied = $state(false);

  async function copy(): Promise<void> {
    try {
      await navigator.clipboard.writeText(serverId);
      copied = true;
      setTimeout(() => (copied = false), 2000);
    } catch {
      // Kopiëren geweigerd: het id staat leesbaar in het veld en is te selecteren.
    }
  }
</script>

<Panel>
  {#snippet title()}{t('admin.net.identity.title')}{/snippet}
  <div class="stack">
    <div>
      <Field
        label={t('admin.set.field.server_name')}
        bind:value={draft.name}
        error={errors.name}
        hint={t('admin.net.identity.nameHint')}
        autocomplete="off"
      />
      <SettingSourceHint source={settings.server_name.source} env={SETTING_ENV.server_name} />
    </div>
    <div class="idrow">
      <div class="idfield">
        <Field label={t('admin.net.identity.id')} value={serverId} mono>
          {#snippet children(control)}
            <input id={control.id} type="text" value={serverId} readonly class="mono" />
          {/snippet}
        </Field>
      </div>
      <button type="button" class="btn btn--secondary btn--sm" onclick={() => void copy()}>
        {copied ? t('admin.set.copied') : t('admin.set.copy')}
      </button>
    </div>
    <div>
      <Field
        label={t('admin.set.field.public_url')}
        type="url"
        bind:value={draft.publicUrl}
        error={errors.publicUrl}
        hint={t('admin.net.identity.publicHint')}
        placeholder={EXAMPLE_ADDRESS}
        autocomplete="off"
      />
      <SettingSourceHint source={settings.public_url.source} env={SETTING_ENV.public_url} />
    </div>
  </div>
</Panel>

<style>
  .stack {
    display: grid;
    gap: 18px;
  }

  .idrow {
    display: flex;
    align-items: flex-end;
    gap: 10px;
  }

  .idfield {
    flex: 1 1 auto;
    min-width: 0;
  }
</style>
