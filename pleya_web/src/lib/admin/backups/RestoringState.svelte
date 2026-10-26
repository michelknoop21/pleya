<!--
  Wat de pagina toont zodra een restore gestart is: de server is weg en de
  lijst van daarvoor zou een verouderd beeld geven, dus de pagina vervangt hem
  door deze staat tot de server weer antwoordt. Er is geen knop om opnieuw te
  restoren: de enige uitwegen zijn controleren, de lijst, het logboek of
  inloggen.
-->
<script lang="ts">
  import StateView from '../../components/StateView.svelte';
  import { t } from '../../i18n';

  interface Props {
    phase: 'waiting' | 'back' | 'signin' | 'timeout';
    onlist: () => void;
    oncheck: () => void;
  }

  let { phase, onlist, oncheck }: Props = $props();
</script>

{#if phase === 'waiting'}
  <StateView alert={false} title={t('admin.bak.wait.title')} message={t('admin.bak.wait.body')} />
{:else if phase === 'back'}
  <StateView alert={false} title={t('admin.bak.back.title')} message={t('admin.bak.back.body')}>
    {#snippet actions()}
      <button type="button" class="btn btn--sm" onclick={onlist}>{t('admin.bak.back.list')}</button>
      <a class="btn btn--secondary btn--sm" href="/admin/diagnostics">{t('admin.bak.back.log')}</a>
    {/snippet}
  </StateView>
{:else if phase === 'signin'}
  <StateView kind="error" title={t('admin.bak.signin.title')} message={t('admin.bak.signin.body')}>
    {#snippet actions()}
      <a class="btn btn--sm" href="/login">{t('admin.bak.signin.action')}</a>
    {/snippet}
  </StateView>
{:else}
  <StateView kind="error" title={t('admin.bak.timeout.title')} message={t('admin.bak.timeout.body')}>
    {#snippet actions()}
      <button type="button" class="btn btn--secondary btn--sm" onclick={oncheck}>
        {t('admin.bak.timeout.action')}
      </button>
    {/snippet}
  </StateView>
{/if}
