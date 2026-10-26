<!-- `/admin/libraries/{id}`: scherm 22 (bewerken) met 23 (verwijderen) als dialoog. -->
<script lang="ts">
  import { page } from '$app/state';

  import LibraryEditor from '$lib/admin/LibraryEditor.svelte';
  import { t } from '$lib/i18n';

  const id = $derived(page.params['id'] ?? '');
</script>

<svelte:head>
  <title>{t('admin.nav.libraries')} · {t('app.name')}</title>
</svelte:head>

{#key id}
  <LibraryEditor {id} />
{/key}
