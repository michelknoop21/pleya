<!-- `/admin/network`: scherm 30. -->
<script lang="ts">
  import NetworkPage from '#lib/admin/settings/NetworkPage.svelte';
  import { t } from '#lib/i18n/index.js';
</script>

<svelte:head>
  <title>{t('admin.nav.network')} · {t('app.name')}</title>
</svelte:head>

<NetworkPage />
