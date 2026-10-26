<!-- `/admin/libraries`: scherm 21. Een melding na verwijderen of toevoegen komt via de query. -->
<script lang="ts">
  import { page } from '$app/state';

  import LibrariesPage from '$lib/admin/LibrariesPage.svelte';
  import { t } from '$lib/i18n';
</script>

<svelte:head>
  <title>{t('admin.nav.libraries')} · {t('app.name')}</title>
</svelte:head>

<LibrariesPage
  removed={page.url.searchParams.get('removed')}
  added={page.url.searchParams.get('added')}
/>
