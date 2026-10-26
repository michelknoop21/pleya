<!-- `/admin/security/agents`: scherm 34, Agents en API-tokens. -->
<script lang="ts">
  import TokensPage from '$lib/admin/tokens/TokensPage.svelte';
  import { t } from '$lib/i18n';
</script>

<svelte:head>
  <title>{t('admin.tok.title')} · {t('app.name')}</title>
</svelte:head>

<TokensPage />
