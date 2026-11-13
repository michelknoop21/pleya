<!--
  De paginamelding uit pageNotice, bovenaan de inhoud van de schil. Hij hoort
  bij één pad: wie verder navigeert ziet hem niet terug. De regels zijn tekst,
  ook als een bestandsnaam op HTML lijkt.
-->
<script lang="ts">
  import Alert from './Alert.svelte';
  import { pageNotice } from '../stores/pageNotice.svelte';

  let { path }: { path: string } = $props();

  const notice = $derived(pageNotice.current?.path === path ? pageNotice.current : null);
  $effect(() => {
    if (pageNotice.current && pageNotice.current.path !== path) pageNotice.current = null;
  });
</script>

{#if notice}
  <div class="notice">
    <Alert tone={notice.tone}>
      {notice.text}
      {#if notice.lines.length > 0}
        <ul class="notice__lines">{#each notice.lines as line, index (index)}<li>{line}</li>{/each}</ul>
      {/if}
    </Alert>
  </div>
{/if}

<style>
  .notice { padding: var(--space-1-5) var(--inset) 0; }
  .notice__lines { margin: 8px 0 0; padding-left: 18px; overflow-wrap: anywhere; }
</style>
