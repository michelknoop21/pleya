<!--
  Nu aan het kijken, het eerste blok van het overzicht: een kaart per kijker.
  Eerst de browserstreams uit `GET /stream-sessions` (direct play), dan de
  omzetsessies uit `GET /transcode-sessions`, oudste eerst. De twee lijsten
  delen geen sleutel waarmee een omzetsessie aan een titel te hangen is, dus
  elke regel van de server is één kaart; zie ViewerCard.

  De streamlijst kent alleen de browser. Wat een app direct afspeelt staat er
  niet in, en de lege staat zegt dat.
-->
<script lang="ts">
  import { t } from '../i18n';
  import { countLabel, type OverviewData } from './overview';
  import { sortedSessions } from './transcode/transcode';
  import ViewerCard from './ViewerCard.svelte';

  interface Props {
    data: OverviewData;
    /** Omzetsessies waarvoor nu een stopaanvraag loopt. */
    stopping?: Record<string, boolean>;
    onstop?: (id: string, name: string) => void;
  }

  let { data, stopping = {}, onstop }: Props = $props();

  const uid = $props.id();
  const sessions = $derived(sortedSessions(data.transcode.items));
  const total = $derived(data.streams.length + sessions.length);
  const summary = $derived(
    [
      countLabel('admin.watching.viewers', total),
      ...(sessions.length > 0 ? [countLabel('admin.watching.conversions', sessions.length)] : [])
    ].join(' · ')
  );
</script>

<section class="watching" aria-labelledby={`${uid}-title`}>
  <div class="head">
    <h3 class="title" id={`${uid}-title`}>{t('admin.watching.title')}</h3>
    {#if total > 0}
      <p class="count">{summary}</p>
    {/if}
  </div>
  {#if total === 0}
    <p class="empty">{t('admin.watching.empty')}</p>
  {:else}
    <div class="cards">
      {#each data.streams as stream (stream.id)}
        <ViewerCard {stream} />
      {/each}
      {#each sessions as session (session.id)}
        <ViewerCard {session} users={data.users} stopping={stopping[session.id]} {onstop} />
      {/each}
    </div>
  {/if}
</section>

<style>
  .watching {
    min-width: 0;
  }

  .head {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    justify-content: space-between;
    gap: 4px 16px;
    margin-bottom: 10px;
  }

  .title {
    margin: 0;
    font-size: 16px;
    font-weight: 600;
    line-height: 1.3;
    letter-spacing: -0.01em;
    color: var(--ink);
  }

  .count {
    margin: 0;
    font-size: 13px;
    color: var(--ink-3);
    font-variant-numeric: tabular-nums;
  }

  .empty {
    margin: 0;
    padding: 16px 18px;
    border: 1px solid var(--hairline);
    border-radius: var(--radius-panel);
    background: var(--panel);
    font-size: 14px;
    color: var(--ink-3);
  }

  .cards {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(100%, 340px), 1fr));
    gap: 14px;
  }
</style>
