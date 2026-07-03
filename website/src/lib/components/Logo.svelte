<script lang="ts">
  import mark from '$lib/assets/pleya_logo.png';

  let { class: className = '', alt = '' }: { class?: string; alt?: string } = $props();
</script>

<img src={mark} {alt} class={className} draggable="false" />

<style>
  img {
    display: block;
    width: 100%;
    height: auto;
    user-select: none;
  }
</style>
