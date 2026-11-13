<!--
  "Bestand" onderaan het filmdetail: wat `GET /items/{id}` over de gekozen
  versie en de herkomst zegt. Het contract levert geen pad, bestandsgrootte,
  bitrate of bibliotheeknaam, dus die regels bestaan hier niet. Een regel
  zonder waarde valt weg.
-->
<script lang="ts">
  import type { Item, Version } from '../api/types';
  import { t } from '../i18n';
  import { formatDate, formatDuration } from '../util/format';

  let { item, version }: { item: Item; version: Version | undefined } = $props();

  const rows = $derived.by(() => {
    const video = (version?.video_streams ?? []).map(stream => [
      stream.codec,
      stream.profile,
      stream.width && stream.height ? `${stream.width}×${stream.height}` : null,
      stream.bit_depth ? `${stream.bit_depth}-bit` : null,
      stream.frame_rate ? `${stream.frame_rate.toFixed(3)} fps` : null
    ].filter(Boolean).join(' · ')).filter(Boolean).join('\n');
    const tmdb = item.applied_external_ids?.tmdb ?? item.external_ids?.tmdb;
    return [
      { label: t('item.video'), value: video },
      { label: t('detail.file.format'), value: version ? [version.container, formatDuration(version.duration_ms)].filter(Boolean).join(' · ') : '' },
      { label: t('item.added'), value: formatDate(item.added_at) ?? '' },
      { label: t('detail.file.source'), value: tmdb ? `${t('admin.metadata.editor.source.tmdb')} ${tmdb}` : '' }
    ].filter(row => row.value);
  });
</script>

{#if rows.length > 0}
  <section class="file" aria-labelledby="file-facts">
    <h2 class="file__h" id="file-facts">{t('detail.file')}</h2>
    <dl class="file__rows">
      {#each rows as row (row.label)}
        <div class="file__row"><dt>{row.label}</dt><dd>{row.value}</dd></div>
      {/each}
    </dl>
  </section>
{/if}

<style>
  .file { display: flex; flex-direction: column; gap: var(--space); min-width: 0; }
  .file__h { margin: 0; font-size: 20px; font-weight: 700; letter-spacing: -0.01em; color: var(--ink); }
  .file__rows { display: grid; gap: var(--space-half); margin: 0; }
  .file__row { display: grid; grid-template-columns: 110px minmax(0, 1fr); gap: var(--space); align-items: baseline; }
  .file__row dt { color: var(--ink-2); font-size: 13px; }
  .file__row dd { margin: 0; white-space: pre-line; overflow-wrap: anywhere; }
  @media (max-width: 899px) { .file__h { font-size: 18px; } }
</style>
