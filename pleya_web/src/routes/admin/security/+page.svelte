<!-- `/admin/security`: scherm 31. -->
<script lang="ts">
  import SecurityPage from '$lib/admin/settings/SecurityPage.svelte';
  import { t } from '$lib/i18n';
</script>

<svelte:head>
  <title>{t('admin.nav.security')} · {t('app.name')}</title>
</svelte:head>

<SecurityPage />
