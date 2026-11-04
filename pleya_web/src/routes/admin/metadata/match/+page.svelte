<!-- `/admin/metadata/match`: scherm 36. In de northstar hangt Match en overrides onder Metadata en artwork. -->
<script lang="ts">
  import { page } from '$app/state';
  import MatchPage from '#lib/admin/match/MatchPage.svelte';
  import { t } from '#lib/i18n/index.js';
</script>

<svelte:head>
  <title>{t('admin.match.title')} · {t('app.name')}</title>
</svelte:head>

<MatchPage initialItem={page.url.searchParams.get('item')} />
