<!--
  De instellingen van de back-ups, alleen lezen, met de naam van de
  omgevingsvariabele erbij. Ze staan bewust niet in `PATCH /settings`: een
  bewaartermijn die via de API omlaag kan, kan ook omlaag door een overgenomen
  beheerdersaccount, en dan ruimt de server zelf de back-ups op die hem hadden
  moeten redden.

  De sleutel voor de geheimen wordt nooit getoond, ook niet gemaskeerd: de
  server geeft alleen `secrets_key_configured`, en dat is wat hier staat.
-->
<script lang="ts">
  import Panel from '../../components/Panel.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import type { BackupList } from '../../api/types';
  import { t } from '../../i18n';
  import FactList from '../settings/FactList.svelte';
  import { BACKUP_ENV, daysLabel } from './backups';

  let { list }: { list: BackupList } = $props();
</script>

<Panel>
  {#snippet title()}{t('admin.bak.settings.title')}{/snippet}
  <FactList>
    <dt>{t('admin.bak.settings.dir')}</dt>
    <dd>
      <span class="mono">{list.dir}</span>
      <span class="sub mono">{BACKUP_ENV.dir}</span>
    </dd>
    <dt>{t('admin.bak.settings.time')}</dt>
    <dd>
      {t('admin.bak.settings.timeValue', { time: list.schedule })}
      <span class="sub mono">{BACKUP_ENV.schedule}</span>
    </dd>
    <dt>{t('admin.bak.settings.retention')}</dt>
    <dd>
      {daysLabel(list.retention_days)}
      <span class="sub mono">{BACKUP_ENV.retention}</span>
      <span class="sub">{t('admin.bak.settings.retentionNote')}</span>
    </dd>
    <dt>{t('admin.bak.settings.key')}</dt>
    <dd>
      <StatusPill
        size="sm"
        tone={list.secrets_key_configured ? 'ok' : 'warn'}
        label={list.secrets_key_configured ? t('admin.bak.settings.keySet') : t('admin.bak.settings.keyNotSet')}
      />
      <span class="sub mono">{BACKUP_ENV.key}</span>
    </dd>
  </FactList>
  <p class="help">{t('admin.bak.settings.help')}</p>
</Panel>

<style>
  .help {
    margin: 14px 0 0;
    font-size: 12px;
    line-height: 1.5;
    color: var(--ink-3);
  }
</style>
