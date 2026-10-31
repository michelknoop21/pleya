<script lang="ts">
  import { page } from '$app/state';
  import ListDetail from '#lib/components/lists/ListDetail.svelte';
</script>

<ListDetail kind="playlist" id={page.params['id'] ?? ''} />
