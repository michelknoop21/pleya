<script lang="ts">
  import type { Snippet } from 'svelte';
  import { t } from '../../i18n';
  import type { MetadataOverrideField } from '../../api/types';
  let { field, source, locked, dirty, disabled, onunlock, children }: {
    field: MetadataOverrideField; source: string; locked: boolean; dirty: boolean;
    disabled: boolean; onunlock: () => void; children: Snippet;
  } = $props();
  const label = $derived(t(`admin.metadata.editor.field.${field}`));
  const sourceLabel = $derived(source === 'manual' ? t('admin.metadata.editor.source.manual') : source === 'tmdb' ? t('admin.metadata.editor.source.tmdb') : source === 'nfo' ? t('admin.metadata.editor.source.nfo') : source === 'scanner' ? t('admin.metadata.editor.source.scanner') : source === 'none' ? t('admin.metadata.editor.source.none') : t('admin.metadata.editor.source.unknown'));
</script>
<section class="metadata-field" aria-label={label}>
  <div class="field-head">
    <div>
      <h3>{label}</h3>
      <p class="provenance"><span>{t('admin.metadata.editor.source', { source: sourceLabel })}</span><span class:locked>{locked ? t('admin.metadata.editor.locked') : t('admin.metadata.editor.unlocked')}</span></p>
      {#if dirty && !locked}<p class="pending">{t('admin.metadata.editor.pending')}</p>{/if}
    </div>
    {#if locked}<button type="button" class="btn btn--secondary btn--sm" aria-label={t('admin.metadata.editor.unlock', { field: label })} {disabled} onclick={onunlock}>{t('admin.metadata.editor.unlockAction')}</button>{/if}
  </div>
  {@render children()}
</section>
<style>
  .metadata-field { min-width: 0; padding-block: 22px; border-top: 1px solid var(--hairline-strong); }
  .field-head { display: flex; justify-content: space-between; align-items: start; gap: 16px; margin-bottom: 12px; }
  h3 { margin: 0 0 5px; font-size: 15px; font-weight: 650; }
  .provenance { display: flex; gap: 6px 16px; flex-wrap: wrap; margin: 0; color: var(--ink-2); font-size: 12px; }
  .locked { color: var(--ink); font-weight: 600; }
  .pending { margin: 5px 0 0; color: var(--ink-2); font-size: 12px; }
  @media (max-width: 540px) { .field-head { flex-direction: column; gap: 10px; } }
</style>
