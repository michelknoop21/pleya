<!-- `/admin/users/new`: een gebruiker toevoegen (geen eigen northstar-scherm, zie UserCreate). -->
<script lang="ts">
  import UserCreate from '$lib/admin/UserCreate.svelte';
  import { t } from '$lib/i18n';
</script>

<svelte:head>
  <title>{t('admin.users.action.add')} · {t('app.name')}</title>
</svelte:head>

<UserCreate />
