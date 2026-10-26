<!-- `/admin/media/transcode`: scherm 37, Transcode-sessies. -->
<script lang="ts">
  import TranscodePage from '#lib/admin/transcode/TranscodePage.svelte';
  import { t } from '#lib/i18n/index.js';
</script>

<svelte:head>
  <title>{t('admin.tc.title')} · {t('app.name')}</title>
</svelte:head>

<TranscodePage />
