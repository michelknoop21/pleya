<!-- `/admin/metadata`: scherm 29. -->
<script lang="ts">
  import MetadataPage from '#lib/admin/settings/MetadataPage.svelte';
  import { t } from '#lib/i18n/index.js';
</script>

<svelte:head>
  <title>{t('admin.nav.metadata')} · {t('app.name')}</title>
</svelte:head>

<MetadataPage />
