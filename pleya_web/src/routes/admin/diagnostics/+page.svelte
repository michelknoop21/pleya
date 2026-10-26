<!-- `/admin/diagnostics`: scherm 32. -->
<script lang="ts">
  import DiagnosticsPage from '$lib/admin/settings/DiagnosticsPage.svelte';
  import { t } from '$lib/i18n';
</script>

<svelte:head>
  <title>{t('admin.nav.diagnostics')} · {t('app.name')}</title>
</svelte:head>

<DiagnosticsPage />
