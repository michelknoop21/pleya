<script lang="ts">
  import type { Row } from './asks';
  // A card of rows as the app draws them: watch stats, a comparison between servers, or the
  // list of what Pleya carried out.
  let { label, note, items }: { label: string; note?: string; items: Row[] } = $props();
</script>

<div class="rows">
  <p class="label"><span>{label}</span>{#if note}<span class="note">{note}</span>{/if}</p>
  <ul>
    {#each items as r, i (i)}
      <li>
        <span class="txt"><strong>{r.title}</strong>{#if r.sub}<span>{r.sub}</span>{/if}</span>
        {#if r.pill}<span class="pill {r.tone ?? 'plain'}">{r.pill}</span>{/if}
      </li>
    {/each}
  </ul>
</div>

<style>
  .rows { padding: 1.1rem 1.2rem 0.5rem; border-radius: 1.1rem; background: rgba(22, 22, 22, 0.9); }
  .label { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 0.3rem 1rem; color: rgba(244, 241, 236, 0.66); font-size: 0.9rem; }
  .note { color: var(--ink); font-variant-numeric: tabular-nums; }
  ul { margin-top: 0.6rem; }
  li { display: flex; align-items: center; justify-content: space-between; gap: 1rem; padding-block: 0.75rem; border-top: 1px solid rgba(255, 255, 255, 0.08); }
  .txt { display: grid; gap: 0.1rem; min-width: 0; }
  strong { font-size: 1.08rem; font-weight: 700; }
  .txt span { color: rgba(244, 241, 236, 0.66); font-size: 0.9rem; }
  .pill { flex: none; padding: 0.1rem 0.8rem; border-radius: 999px; background: rgba(244, 241, 236, 0.16); font-size: 0.86rem; font-variant-numeric: tabular-nums; white-space: nowrap; }
  .pill.ok { background: rgba(61, 214, 140, 0.16); color: #3dd68c; }
  .pill.requested { background: rgba(255, 176, 32, 0.16); color: var(--amber); }
</style>
