<!-- `/admin/storage`: scherm 24. -->
<script lang="ts">
  import StoragePage from '$lib/admin/StoragePage.svelte';
  import { t } from '$lib/i18n';
</script>

<svelte:head>
  <title>{t('admin.nav.storage')} · {t('app.name')}</title>
</svelte:head>

<StoragePage />
