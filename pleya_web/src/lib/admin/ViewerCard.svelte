<!--
  Eén kijker in het blok Nu aan het kijken van het overzicht. Twee vormen,
  omdat de server twee lijsten heeft die niet aan elkaar te koppelen zijn:

  - een browserstream uit `GET /stream-sessions`. Die bestaat alleen bij direct
    play (zie player/delivery.ts), dus de kaart zegt dat zonder te gokken:
    titel, gebruiker, toestel en de voortgang als de server een positie meldt.
    Er is geen route om zo'n stream te stoppen, dus er staat geen knop.
  - een omzetsessie uit `GET /transcode-sessions`: gebruiker, versie, soort
    omzetting, hardware en Stoppen (`DELETE /transcode-sessions/{id}`). Titel,
    toestel en voortgang draagt die lijst niet, dus die regels ontbreken.

  Stoppen vraagt de bevestiging van het overzicht; de kaart stuurt zelf niets.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import type { StreamSessionSummary, TranscodeSession, User } from '../api/types';
  import { knownDeviceName } from '../auth/device';
  import { t } from '../i18n';
  import { formatDuration, formatRelative } from '../util/format';
  import { modeLabel, userName } from './settings/media';
  import { streamProgress } from './overview';
  import { shortId } from './transcode/transcode';

  interface Props {
    stream?: StreamSessionSummary;
    session?: TranscodeSession;
    users?: User[] | null;
    stopping?: boolean;
    onstop?: (id: string, name: string) => void;
  }

  let { stream, session, users = null, stopping = false, onstop = () => {} }: Props = $props();

  const progress = $derived(stream ? streamProgress(stream) : null);
  const name = $derived(session ? userName(users, session.user_id) : '');
  const hardware = $derived(
    session?.hw_accel ? session.hw_accel.toUpperCase() : t('admin.media.transcode.software')
  );
  const started = $derived(formatRelative(stream?.started_at ?? session?.started_at) ?? '');
</script>

<article class="card" data-viewer={stream?.id ?? session?.id}>
  <div class="top">
    <span class="thumb" aria-hidden="true"><AdminIcon name="tv" size={22} /></span>
    <div class="body">
      {#if stream}
        <h4 class="title">{stream.item_title}</h4>
        <p class="who">
          {stream.username} · {knownDeviceName(stream.device_name) ?? t('admin.watching.unknownDevice')}
        </p>
      {:else if session}
        <h4 class="title">{t('admin.watching.session')}</h4>
        <p class="who">
          {name} · <span class="mono">{t('admin.tc.version', { id: shortId(session.version_id) })}</span>
        </p>
      {/if}
    </div>
  </div>

  {#if stream && progress !== null}
    <progress
      class="bar"
      value={progress}
      max="100"
      aria-label={t('admin.watching.progress', { percent: progress })}
    ></progress>
    <p class="meta">
      {progress}% · {t('admin.watching.position', {
        position: formatDuration(stream.position_ms) ?? t('duration.s', { s: 0 }),
        duration: formatDuration(stream.duration_ms) ?? ''
      })}
    </p>
  {/if}

  <div class="foot">
    <div class="state">
      {#if stream}
        <StatusPill size="sm" tone="ok" label={t('player.mode.direct_play')} />
      {:else if session}
        <StatusPill
          size="sm"
          tone="run"
          label={t('admin.watching.converting', {
            detail: session.mode === 'transcode' ? hardware : `${modeLabel(session.mode)} · ${hardware}`
          })}
        />
      {/if}
      {#if started}<span class="since">{t('admin.activity.started', { when: started })}</span>{/if}
    </div>
    {#if session}
      <button
        type="button"
        class="btn btn--secondary btn--sm"
        disabled={stopping}
        aria-label={t('admin.media.transcode.stopNamed', { name })}
        onclick={() => session && onstop(session.id, name)}
      >
        <AdminIcon name="stop" size={14} />{stopping ? t('admin.tc.stopping') : t('admin.media.transcode.stop')}
      </button>
    {/if}
  </div>
</article>

<style>
  .card {
    display: grid;
    gap: 12px;
    min-width: 0;
    padding: 16px 18px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-panel);
    background: var(--panel);
    box-shadow: var(--ring-shadow);
  }

  .top {
    display: flex;
    align-items: center;
    gap: 14px;
    min-width: 0;
  }

  .thumb {
    display: grid;
    place-items: center;
    flex: none;
    width: 44px;
    height: 44px;
    border-radius: var(--radius-sm);
    background: var(--fill);
    color: var(--ink-3);
  }

  .body {
    flex: 1;
    min-width: 0;
  }

  .title,
  .who {
    margin: 0;
    overflow-wrap: anywhere;
  }

  .title {
    font-size: 16px;
    font-weight: 600;
    line-height: 1.3;
    color: var(--ink);
  }

  .who {
    margin-top: 2px;
    font-size: 13px;
    color: var(--ink-2);
  }

  .who .mono {
    font-size: 12px;
  }

  .bar {
    display: block;
    width: 100%;
    height: 4px;
    border: 0;
    border-radius: var(--radius-pill);
    background: var(--fill-2);
    overflow: hidden;
    appearance: none;
  }

  .bar::-webkit-progress-bar {
    background: var(--fill-2);
  }

  .bar::-webkit-progress-value {
    background: var(--accent);
  }

  .bar::-moz-progress-bar {
    background: var(--accent);
  }

  .meta {
    margin: -4px 0 0;
    font-size: 13px;
    color: var(--ink-3);
    font-variant-numeric: tabular-nums;
  }

  .foot {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 10px 12px;
  }

  .state {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px 10px;
    min-width: 0;
  }

  .since {
    font-size: 13px;
    color: var(--ink-3);
  }
</style>
