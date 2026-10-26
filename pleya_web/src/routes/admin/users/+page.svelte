<!-- `/admin/users`: scherm 26. Een melding na verwijderen komt via de query. -->
<script lang="ts">
  import { page } from '$app/state';

  import UsersPage from '#lib/admin/UsersPage.svelte';
  import { t } from '#lib/i18n/index.js';
</script>

<svelte:head>
  <title>{t('admin.nav.users')} · {t('app.name')}</title>
</svelte:head>

<UsersPage removed={page.url.searchParams.get('removed')} />
