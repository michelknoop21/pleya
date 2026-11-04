<!--
  Een fout uit bibliotheekbeheer als rode melding met één uitweg: opnieuw
  proberen, opnieuw laden, overnemen, of een link naar de plek waar het op te
  lossen is. Welke uitweg bij welke code hoort staat in libraryErrors.ts.
-->
<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import { t } from '../i18n';
  import type { LibraryProblem } from './libraryErrors';

  interface Props {
    problem: LibraryProblem;
    onretry?: () => void;
    onreload?: () => void;
    onadopt?: () => void;
  }

  let { problem, onretry, onreload, onadopt }: Props = $props();
</script>

<Alert tone="err">
  {problem.message}
  {#snippet actions()}
    {#if problem.wayOut === 'retry' && onretry}
      <button type="button" class="btn btn--secondary btn--sm" onclick={onretry}>
        {t('common.retry')}
      </button>
    {:else if problem.wayOut === 'reload' && onreload}
      <button type="button" class="btn btn--secondary btn--sm" onclick={onreload}>
        {t('admin.lib.action.reload')}
      </button>
    {:else if problem.wayOut === 'adopt' && onadopt}
      <button type="button" class="btn btn--secondary btn--sm" onclick={onadopt}>
        {t('admin.lib.action.adopt')}
      </button>
    {:else if problem.wayOut === 'storage'}
      <a class="btn btn--secondary btn--sm" href="/admin/storage">{t('admin.alert.action')}</a>
    {:else if problem.wayOut === 'activity'}
      <a class="btn btn--secondary btn--sm" href="/admin/activity">{t('admin.lib.action.activity')}</a>
    {:else if problem.wayOut === 'list'}
      <a class="btn btn--secondary btn--sm" href="/admin/libraries">{t('admin.lib.action.toList')}</a>
    {:else if problem.wayOut === 'login'}
      <a class="btn btn--secondary btn--sm" href="/login">{t('admin.lib.action.login')}</a>
    {:else if problem.wayOut === 'home'}
      <a class="btn btn--secondary btn--sm" href="/">{t('admin.nav.back')}</a>
    {/if}
  {/snippet}
</Alert>
