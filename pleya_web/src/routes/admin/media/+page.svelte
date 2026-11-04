<!-- `/admin/media`: scherm 28. -->
<script lang="ts">
  import MediaPage from '#lib/admin/settings/MediaPage.svelte';
  import { t } from '#lib/i18n/index.js';
</script>

<svelte:head>
  <title>{t('admin.nav.media')} · {t('app.name')}</title>
</svelte:head>

<MediaPage />
