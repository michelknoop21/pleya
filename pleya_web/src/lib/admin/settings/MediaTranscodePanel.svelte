<!--
  Transcoderen (28, rechts): de hardwarestatus die de server bij het opstarten
  meet, het maximum aantal gelijktijdige omzettingen (een omgevingsvariabele,
  dus alleen lezen) en de lopende sessies met Stoppen
  (`DELETE /transcode-sessions/{id}`).

  Bewust niet gebouwd, omdat de server het niet als instelling kent: de keuze
  van een hardwarebackend, een kwaliteitsladder, ondertitels bij transcoderen,
  een transcodemap met quotum, en per backend (QSV, NVENC) een eigen regel. De
  server meldt alleen `accel` (`none` of `vaapi`) met de reden.
-->
<script lang="ts">
  import type { TranscodeSessionList, User } from '../../api/types';
  import AdminIcon from '../../components/AdminIcon.svelte';
  import Panel from '../../components/Panel.svelte';
  import StatusPill from '../../components/StatusPill.svelte';
  import { plural, t } from '../../i18n';
  import { formatRelative } from '../../util/format';
  import FactList from './FactList.svelte';
  import { ENV_MAX_TRANSCODES, modeLabel, userName } from './media';

  interface Props {
    transcode: TranscodeSessionList;
    users: User[] | null;
    /** `capabilities.transcode`: zonder omzetter staat het hele paneel op uit. */
    available: boolean;
    stopping: Record<string, boolean>;
    onstop: (id: string, name: string) => void;
  }

  let { transcode, users, available, stopping, onstop }: Props = $props();

  const count = $derived(transcode.items.length);
</script>

<Panel>
  {#snippet title()}{t('admin.media.transcode.title')}{/snippet}
  {#snippet actions()}
    <StatusPill
      variant="dot"
      tone={available ? 'ok' : 'idle'}
      label={available
        ? plural('admin.media.transcode.on', count)
        : t('admin.media.transcode.off')}
    />
  {/snippet}

  <FactList>
    <dt>{t('admin.media.transcode.hardware')}</dt>
    <dd>
      {#if transcode.hardware.accel === 'none'}
        <StatusPill variant="dot" tone="idle" label={t('admin.media.transcode.hwNone')} />
        {#if transcode.hardware.reason}<span class="muted"> · {transcode.hardware.reason}</span>{/if}
      {:else}
        <StatusPill variant="dot" tone="ok" label={t('admin.media.transcode.hwOn', { accel: transcode.hardware.accel.toUpperCase() })} />
      {/if}
    </dd>
    <dt>{t('admin.media.transcode.max')}</dt>
    <dd>
      {#if transcode.max_sessions === 0}
        <span class="muted">{t('admin.media.transcode.maxZero')}</span>
      {:else}
        {transcode.max_sessions}
      {/if}
      <span class="muted">· {t('admin.media.analysis.env')}</span>
      <span class="sub mono">{ENV_MAX_TRANSCODES}</span>
    </dd>
  </FactList>
  <p class="note">{t('admin.media.transcode.hint')}</p>

  {#if available}
    <h4 class="sub">{t('admin.media.transcode.running')}</h4>
    <!-- Scherm 37 is de volwaardige pagina voor dezelfde sessies. -->
    <a class="all" href="/admin/media/transcode">{t('admin.tc.panelLink')}</a>
    {#if count === 0}
      <p class="note">{t('admin.media.transcode.none')}</p>
    {:else}
      <ul class="list">
        {#each transcode.items as item (item.id)}
          {@const name = userName(users, item.user_id)}
          <li class="row" data-session={item.id}>
            <span class="ico"><AdminIcon name="tv" size={18} /></span>
            <span class="text">
              <span class="who">{name}</span>
              <span class="meta">
                {modeLabel(item.mode)}{item.hw_accel ? ` · ${item.hw_accel.toUpperCase()}` : ` · ${t('admin.media.transcode.software')}`}
                · {t('admin.media.transcode.since', { when: formatRelative(item.started_at) ?? '' })}
              </span>
            </span>
            <button
              type="button"
              class="btn btn--secondary btn--sm"
              disabled={stopping[item.id]}
              aria-label={t('admin.media.transcode.stopNamed', { name })}
              onclick={() => onstop(item.id, name)}
            >
              <AdminIcon name="stop" size={14} />{t('admin.media.transcode.stop')}
            </button>
          </li>
        {/each}
      </ul>
    {/if}
  {/if}
</Panel>

<style>
  .note {
    margin: 10px 0 0;
    font-size: 12.5px;
    line-height: 1.5;
    color: var(--ink-3);
  }

  .sub {
    margin: 16px 0 6px;
    font-size: 13px;
    font-weight: 600;
    color: var(--ink-2);
  }

  .list {
    display: grid;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 0;
    border-bottom: 1px solid var(--hairline);
  }

  .row:last-child {
    border-bottom: 0;
  }

  .ico {
    flex: none;
    color: var(--ink-3);
  }

  .text {
    display: grid;
    flex: 1 1 auto;
    min-width: 0;
  }

  .who {
    font-size: 14px;
    font-weight: 600;
    color: var(--ink);
  }

  .meta {
    font-size: 12.5px;
    color: var(--ink-3);
  }

  .muted {
    color: var(--ink-3);
  }

  .all {
    display: inline-block;
    margin-bottom: 6px;
    font-size: 13px;
    font-weight: 600;
    color: var(--ink-2);
  }
</style>
