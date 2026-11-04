<!-- `/admin/diagnostics`: scherm 32. -->
<script lang="ts">
  import DiagnosticsPage from '#lib/admin/settings/DiagnosticsPage.svelte';
  import { t } from '#lib/i18n/index.js';
</script>

<svelte:head>
  <title>{t('admin.nav.diagnostics')} · {t('app.name')}</title>
</svelte:head>

<DiagnosticsPage />
