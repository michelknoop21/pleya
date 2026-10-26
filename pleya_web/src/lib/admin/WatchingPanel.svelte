<!--
  Nu aan het kijken op scherm 20, uit `GET /stream-sessions`: wie, op welk
  toestel, welk item en hoe ver. Die lijst kent alleen streams via de browser;
  wat een app buiten de browser afspeelt, staat er niet in. Seizoen en
  aflevering ("S2 · A3") en de afspeelmodus haalt dit paneel niet op: dat zou
  per regel een extra aanvraag zijn (`GET /items/{id}`). Daaronder de
  omzetsessies uit `GET /transcode-sessions`, zodra er een omzetter is.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import Panel from '../components/Panel.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import { t } from '../i18n';
  import { streamProgress, type OverviewData } from './overview';

  let { data }: { data: OverviewData } = $props();
</script>

<Panel>
  {#snippet title()}{t('admin.watching.title')}{/snippet}
  {#if data.streams.length === 0}
    <p class="empty">{t('admin.watching.empty')}</p>
  {:else}
    <ul class="list">
      {#each data.streams as stream (stream.id)}
        {@const progress = streamProgress(stream)}
        <li class="row">
          <AdminIcon name="tv" size={22} />
          <div class="body">
            <p class="t">
              {stream.username} · {stream.device_name ?? t('admin.watching.unknownDevice')}
            </p>
            <p class="s">{stream.item_title}</p>
          </div>
          {#if progress !== null}
            <StatusPill tone="run" label={`${progress}%`} />
          {/if}
        </li>
      {/each}
    </ul>
  {/if}
  {#if data.transcode.max_sessions > 0}
    <p class="foot">
      {t('admin.watching.transcode', {
        count: data.transcode.items.length,
        max: data.transcode.max_sessions,
        accel: data.transcode.hardware.accel
      })}
    </p>
  {/if}
</Panel>

<style>
  .empty,
  .foot {
    margin: 0;
    font-size: 14px;
    color: var(--ink-3);
  }

  .foot {
    margin-top: 12px;
    padding-top: 12px;
    border-top: 1px solid var(--hairline);
    font-size: 13px;
  }

  .list {
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .row {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 8px 0;
  }

  .row + .row {
    border-top: 1px solid var(--hairline);
  }

  .body {
    flex: 1;
    min-width: 0;
  }

  .t,
  .s {
    margin: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .t {
    font-size: 15px;
    font-weight: 500;
    color: var(--ink);
  }

  .s {
    margin-top: 2px;
    font-size: 13px;
    color: var(--ink-3);
  }
</style>
