<script lang="ts">
  import mark from '$lib/assets/pleya-mark.png';

  let { class: className = '', gradient = true }: { class?: string; gradient?: boolean } = $props();
</script>

<img src={mark} alt="Pleya" class={className} />
