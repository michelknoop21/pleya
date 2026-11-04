<!-- De meldingen boven de lijst (scherm 35): elk met een titel en een uitleg die een uitweg noemt. -->
<script lang="ts">
  import Alert from '../../components/Alert.svelte';
  import type { Warning } from './backups';

  let { items }: { items: Warning[] } = $props();
</script>

{#if items.length > 0}
  <div class="warnings">
    {#each items as warning (warning.id)}
      <Alert tone={warning.tone} title={warning.title}>{warning.message}</Alert>
    {/each}
  </div>
{/if}

<style>
  .warnings {
    display: grid;
    gap: 10px;
    margin-bottom: 16px;
  }
</style>
