<script lang="ts">
  // Posters drawn for this page. Film titles are facts and may be named; the films' own
  // artwork belongs to their studios, so none of it is used or imitated here: each poster is
  // one idea from the story in flat shapes, with the title set in the site's display face.
  export type Art = 'martian' | 'mission' | 'redplanet' | 'dune' | 'paddington' | 'knives';
  let { art, title }: { art: Art; title: string } = $props();
  const lines = $derived(title.split(/(?<=:)\s|\s(?=\S+$)/).slice(0, 3));
</script>

<svg class="poster" viewBox="0 0 136 200" aria-hidden="true">
  {#if art === 'martian'}
    <defs><linearGradient id="bpp-martian" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f0a35c" /><stop offset=".55" stop-color="#c2481d" /><stop offset="1" stop-color="#4a1408" /></linearGradient></defs>
    <rect width="136" height="200" fill="url(#bpp-martian)" />
    <circle cx="98" cy="46" r="15" fill="#ffe2b0" opacity=".9" />
    <path d="M0 128 Q40 108 78 124 T136 114 V200 H0Z" fill="#7a2410" />
    <path d="M0 146 Q52 130 136 142 V200 H0Z" fill="#3a0f06" />
    <path d="M68 142 V124 M68 132 Q56 130 55 118 Q67 119 68 132 M68 127 Q80 124 82 113 Q69 114 68 127" stroke="#8fd46a" stroke-width="2.4" fill="#8fd46a" stroke-linecap="round" />
  {:else if art === 'mission'}
    <defs><radialGradient id="bpp-mission" cx=".3" cy=".25" r="1"><stop offset="0" stop-color="#6f93bd" /><stop offset=".6" stop-color="#22354d" /><stop offset="1" stop-color="#0b121c" /></radialGradient></defs>
    <rect width="136" height="200" fill="url(#bpp-mission)" />
    <circle cx="40" cy="150" r="72" fill="#c45a32" />
    <circle cx="40" cy="150" r="72" fill="#000" opacity=".28" transform="translate(14 10)" />
    <ellipse cx="78" cy="70" rx="56" ry="15" fill="none" stroke="#dfe9f5" stroke-width="1.2" transform="rotate(-24 78 70)" opacity=".8" />
    <circle cx="112" cy="46" r="3.6" fill="#fff" />
  {:else if art === 'redplanet'}
    <rect width="136" height="200" fill="#16060a" />
    <circle cx="68" cy="84" r="50" fill="#b3321f" />
    <circle cx="50" cy="70" r="9" fill="#8a2416" /><circle cx="84" cy="100" r="13" fill="#8a2416" /><circle cx="88" cy="62" r="5" fill="#8a2416" />
    <path d="M18 84 A50 50 0 0 0 118 84 A62 40 0 0 1 18 84Z" fill="#000" opacity=".35" />
    <path d="M10 22 L24 22 M17 15 L17 29 M112 150 L122 150 M117 145 L117 155" stroke="#f3d9c9" stroke-width="1" opacity=".7" />
  {:else if art === 'dune'}
    <defs><linearGradient id="bpp-dune" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6d9a0" /><stop offset=".5" stop-color="#e09a4a" /><stop offset="1" stop-color="#8a4a1c" /></linearGradient></defs>
    <rect width="136" height="200" fill="url(#bpp-dune)" />
    <circle cx="44" cy="44" r="12" fill="#fff4dc" /><circle cx="70" cy="30" r="6" fill="#fff4dc" opacity=".85" />
    <path d="M0 118 Q46 84 92 112 T136 96 V200 H0Z" fill="#b8692a" />
    <path d="M0 150 Q60 112 136 146 V200 H0Z" fill="#6e3814" />
    <path d="M30 138 Q62 120 96 138" fill="none" stroke="#3d1d09" stroke-width="5" stroke-linecap="round" />
  {:else if art === 'paddington'}
    <rect width="136" height="200" fill="#1f3f8f" />
    <circle cx="68" cy="100" r="44" fill="#f2a024" />
    <path d="M40 78 Q68 30 96 78Z" fill="#d32a1e" />
    <ellipse cx="68" cy="78" rx="44" ry="8" fill="#d32a1e" />
    <ellipse cx="68" cy="78" rx="44" ry="8" fill="#000" opacity=".18" transform="translate(0 3)" />
    <rect x="52" y="112" width="32" height="22" rx="3" fill="#fff6e6" /><path d="M56 119 H80 M56 126 H74" stroke="#1f3f8f" stroke-width="2" />
  {:else}
    <rect width="136" height="200" fill="#16211c" />
    {#each Array(16) as _, i (i)}
      <path d="M68 30 L72 76 L64 76Z" fill="#c9d3cd" opacity={0.55 + (i % 4) * 0.12} transform="rotate({i * 22.5} 68 92)" />
    {/each}
    <circle cx="68" cy="92" r="16" fill="#16211c" /><circle cx="68" cy="92" r="6" fill="#b3321f" />
  {/if}
  <rect y="150" width="136" height="50" fill="#000" opacity=".28" />
  <text x="10" y={194 - (lines.length - 1) * 13} class="name">
    {#each lines as line, i (i)}<tspan x="10" dy={i ? 13 : 0}>{line}</tspan>{/each}
  </text>
</svg>

<style>
  .poster { display: block; width: 100%; height: 100%; }
  .name { font-family: var(--display); font-size: 12.5px; font-weight: 800; letter-spacing: -0.01em; fill: #fff; }
</style>
