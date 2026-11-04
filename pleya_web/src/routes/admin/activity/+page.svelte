<!-- `/admin/activity`: scherm 25, Scans en taken. -->
<script lang="ts">
  import ActivityPage from '#lib/admin/ActivityPage.svelte';
  import { t } from '#lib/i18n/index.js';
</script>

<svelte:head>
  <title>{t('admin.nav.activity')} · {t('app.name')}</title>
</svelte:head>

<ActivityPage />
