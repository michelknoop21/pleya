<!--
  De versie van een item in een Panel: container en duur bovenaan, daaronder
  video, audio en ondertitels als lijsten met een eigen kop. Eigen bestand
  omdat de itempagina anders door de 350 regels loopt; er zit geen logica in
  die niet ook op de pagina had kunnen staan.

  Alleen wat `Version` draagt. Een kop zonder streams verschijnt niet: een
  lege lijst onder "Audio" zou beloven dat er audio is.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import Panel from './Panel.svelte';
  import type { Version } from '../api/types';
  import { formatDuration, formatLanguage } from '../util/format';
  import { t } from '../i18n';

  let { version, plain = false, picker }: { version: Version; plain?: boolean; picker?: Snippet } = $props();

  const summary = $derived(
    [version.container, formatDuration(version.duration_ms)].filter(Boolean).join(' · ')
  );
</script>

{#snippet content()}
  <div class="version" class:version--plain={plain}>
    <div class="version__selection">
    {@render picker?.()}
    {#if summary}
      <p class="t-small version__summary">{summary}</p>
    {/if}

    </div>
    <div class="version__av">
    {#if version.video_streams && version.video_streams.length > 0}
      <div class="version__group">
      <h3 class="version__kind">{t('item.video')}</h3>
      <ul class="streams">
        {#each version.video_streams as stream (stream.id)}
          <li class="t-small">
            {[
              stream.codec,
              stream.width && stream.height ? `${stream.width}×${stream.height}` : null,
              stream.bit_depth ? `${stream.bit_depth}-bit` : null,
              stream.frame_rate ? `${stream.frame_rate.toFixed(3)} fps` : null
            ]
              .filter(Boolean)
              .join(' · ')}
          </li>
        {/each}
      </ul>
      </div>
    {/if}

    {#if version.audio_streams && version.audio_streams.length > 0}
      <div class="version__group">
      <h3 class="version__kind">{t('item.audio')}</h3>
      <ul class="streams">
        {#each version.audio_streams as stream (stream.id)}
          <li class="t-small">
            {[
              formatLanguage(stream.language),
              stream.codec,
              stream.channels ? `${stream.channels}ch` : null,
              stream.title,
              stream.is_default ? t('item.default') : null
            ]
              .filter(Boolean)
              .join(' · ')}
          </li>
        {/each}
      </ul>
      </div>
    {/if}

    </div>
    {#if version.subtitle_streams && version.subtitle_streams.length > 0}
      <div class="version__group">
      <h3 class="version__kind">{t('item.subtitles')}</h3>
      <ul class="streams">
        {#each version.subtitle_streams as stream (stream.id)}
          <li class="t-small">
            {[
              formatLanguage(stream.language),
              stream.format,
              stream.is_forced ? t('item.forced') : null,
              stream.is_hearing_impaired ? t('item.sdh') : null,
              stream.is_external ? t('item.external') : null
            ]
              .filter(Boolean)
              .join(' · ')}
          </li>
        {/each}
      </ul>
      </div>
    {/if}
  </div>
{/snippet}
{#if plain}
  {@render content()}
{:else}
  <Panel level={2}>
    {#snippet title()}{t('item.versions')}{/snippet}
    {@render content()}
  </Panel>
{/if}

<style>
  .version {
    display: flex;
    flex-direction: column;
    gap: var(--space-half);
    min-width: 0;
  }

  .version__group { display: flex; flex-direction: column; gap: var(--space-half); min-width: 0; }
  .version--plain { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 24px; border-top: 1px solid var(--hairline); padding-top: 24px; }
  .version__selection, .version__av { display: flex; flex-direction: column; gap: var(--space-half); min-width: 0; }
  .version__av:empty, .version__selection:empty { display: none; }
  @media (max-width: 899px) { .version--plain { grid-template-columns: 1fr; gap: 18px; } }
  .version__summary {
    color: var(--ink-3);
  }

  /* Streamkop in kleine hoofdletters, zoals de kolomkop van DataTable. */
  .version__kind {
    margin: var(--space-half) 0 0;
    font-size: var(--text-caps-size);
    font-weight: 600;
    letter-spacing: var(--text-caps-track);
    text-transform: uppercase;
    color: var(--ink-3);
  }

  .streams {
    display: flex;
    flex-direction: column;
    gap: 2px;
    margin: 0;
    color: var(--ink-2);
  }
</style>
