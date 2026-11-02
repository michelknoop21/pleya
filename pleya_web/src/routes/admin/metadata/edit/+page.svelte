<script lang="ts">
  import { page } from '$app/state';
  import MetadataEditor from '#lib/admin/metadata/MetadataEditor.svelte';
  import { t } from '#lib/i18n/index.js';
</script>
<svelte:head><title>{t('admin.metadata.editor.title')} · {t('app.name')}</title></svelte:head>
<MetadataEditor itemId={page.url.searchParams.get('item') ?? ''} />
