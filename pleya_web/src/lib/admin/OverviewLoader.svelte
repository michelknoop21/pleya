<!--
  Haalt de gegevens van het overzicht op en geeft ze door aan wat het tekent:
  het overzicht (20) of de mobiele index (33). Laden is het compacte skelet,
  een fout is de foutstaat met opnieuw proberen. Mounten gebeurt alleen binnen
  de beheerschil, dus alleen voor een eigenaar of beheerder (S10.7).
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  import SkeletonPage from '../components/SkeletonPage.svelte';
  import StateView from '../components/StateView.svelte';
  import { adminApi } from '../api/admin';
  import { describeError } from '../api/errors';
  import { session } from '../stores/session.svelte';
  import { loadOverview, type OverviewData } from './overview';

  let { children }: { children: Snippet<[OverviewData]> } = $props();

  let data = $state<OverviewData | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);

  $effect(() => {
    void attempt;
    const controller = new AbortController();
    failure = null;
    loadOverview(session.client, adminApi(session.client), controller.signal)
      .then((result) => {
        data = result;
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted) return;
        failure = describeError(err);
      });
    return () => controller.abort();
  });
</script>

{#if data}
  {@render children(data)}
{:else if failure}
  <StateView kind="error" message={failure} onRetry={() => (attempt += 1)} />
{:else}
  <SkeletonPage variant="compact" />
{/if}
