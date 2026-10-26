<!-- `/admin/users/{id}`: scherm 27, met de bevestigingen als dialoog. -->
<script lang="ts">
  import { page } from '$app/state';

  import UserEditor from '$lib/admin/UserEditor.svelte';
  import { t } from '$lib/i18n';

  const id = $derived(page.params['id'] ?? '');
</script>

<svelte:head>
  <title>{t('admin.nav.users')} · {t('app.name')}</title>
</svelte:head>

{#key id}
  <UserEditor {id} added={page.url.searchParams.get('added')} />
{/key}
