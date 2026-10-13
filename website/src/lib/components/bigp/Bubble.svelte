<script lang="ts">
  /** A speech balloon. `text` is the whole line (it sets the size and is what a screen reader gets); `shown` is how much of it Big P has said so far. */
  let { text, shown, tail = 'right' }: { text: string; shown?: string; tail?: 'right' | 'left' | 'down' } = $props();
</script>

<p class="bubble tail-{tail}">
  <span class="sr">{text}</span>
  <span class="ghost" aria-hidden="true">{text}</span>
  <span class="said" aria-hidden="true">{shown ?? text}</span>
</p>

<style>
  .bubble { position: relative; display: inline-block; max-width: 17rem; padding: 0.95rem 1.2rem; border-radius: 1.25rem; background: #f4f1ec; color: #201813; font-size: 1.02rem; font-weight: 500; line-height: 1.35; box-shadow: inset 0 1px 0 #fff, 0 18px 40px -18px #000; }
  .bubble::after { content: ''; position: absolute; width: 1rem; height: 1rem; background: #f4f1ec; transform: rotate(45deg); border-radius: 0 0 3px 0; }
  .tail-right::after { right: 1.6rem; bottom: -0.4rem; }
  .tail-left::after { left: 1.6rem; bottom: -0.4rem; }
  .tail-down::after { left: 50%; bottom: -0.4rem; margin-left: -0.5rem; }
  .ghost { visibility: hidden; }
  .said { position: absolute; inset: 0.95rem 1.2rem auto; }
  .sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; }
</style>
