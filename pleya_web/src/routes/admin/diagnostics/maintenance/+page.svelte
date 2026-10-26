<!-- `/admin/diagnostics/maintenance`: scherm 35. In de northstar hangt Onderhoud onder Diagnostiek. -->
<script lang="ts">
  import BackupsPage from '$lib/admin/backups/BackupsPage.svelte';
  import { t } from '$lib/i18n';
</script>

<svelte:head>
  <title>{t('admin.bak.title')} · {t('app.name')}</title>
</svelte:head>

<BackupsPage />
