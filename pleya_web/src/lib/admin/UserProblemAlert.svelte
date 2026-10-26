<!--
  Een fout uit gebruikersbeheer als rode melding met één uitweg: opnieuw
  proberen, opnieuw laden, terug naar de lijst of inloggen. Welke uitweg bij
  welke code hoort staat in userErrors.ts.
-->
<script lang="ts">
  import Alert from '../components/Alert.svelte';
  import { t } from '../i18n';
  import type { UserProblem } from './userErrors';

  interface Props {
    problem: UserProblem;
    onretry?: () => void;
    onreload?: () => void;
  }

  let { problem, onretry, onreload }: Props = $props();
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
    {:else if problem.wayOut === 'list'}
      <a class="btn btn--secondary btn--sm" href="/admin/users">{t('admin.users.action.toList')}</a>
    {:else if problem.wayOut === 'login'}
      <a class="btn btn--secondary btn--sm" href="/login">{t('admin.lib.action.login')}</a>
    {:else if problem.wayOut === 'home'}
      <a class="btn btn--secondary btn--sm" href="/">{t('admin.nav.back')}</a>
    {/if}
  {/snippet}
</Alert>
