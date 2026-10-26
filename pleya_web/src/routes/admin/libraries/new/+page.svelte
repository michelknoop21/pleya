<!-- `/admin/libraries/new`: scherm 22 in de vorm toevoegen (`POST /libraries`). -->
<script lang="ts">
  import LibraryEditor from '$lib/admin/LibraryEditor.svelte';
  import { t } from '$lib/i18n';
</script>

<svelte:head>
  <title>{t('admin.lib.action.add')} · {t('app.name')}</title>
</svelte:head>

<LibraryEditor id={null} />
