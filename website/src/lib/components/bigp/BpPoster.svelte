<script lang="ts">
  // Posters drawn for this page. Film titles are facts and may be named; the films' own
  // artwork belongs to their studios, so none of it is used or imitated here: each poster is
  // one idea from the story in flat shapes. No lettering: at card size it would be unreadable,
  // and the title stands next to the poster.
  export type Art = 'martian' | 'mission' | 'redplanet' | 'dune' | 'paddington' | 'knives' | 'robot' | 'conclave' | 'sinners';
  let { art }: { art: Art } = $props();
  // Gradient ids are per instance, so the same poster can appear twice on a page.
  const uid = $props.id();
</script>

<svg class="poster" viewBox="0 0 136 200" aria-hidden="true">
  {#if art === 'martian'}
    <defs><linearGradient id="{uid}-g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f0a35c" /><stop offset=".55" stop-color="#c2481d" /><stop offset="1" stop-color="#4a1408" /></linearGradient></defs>
    <rect width="136" height="200" fill="url(#{uid}-g)" />
    <circle cx="98" cy="48" r="16" fill="#ffe2b0" opacity=".9" />
    <path d="M0 132 Q40 112 78 128 T136 118 V200 H0Z" fill="#7a2410" />
    <path d="M0 154 Q52 138 136 150 V200 H0Z" fill="#3a0f06" />
    <path d="M68 152 V126 M68 138 Q52 135 51 119 Q67 121 68 138 M68 131 Q84 127 86 112 Q69 114 68 131" stroke="#8fd46a" stroke-width="3" fill="#8fd46a" stroke-linecap="round" />
  {:else if art === 'mission'}
    <!-- Deep blue and a white ship: the rescue, not the planet. -->
    <defs><linearGradient id="{uid}-g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0c1830" /><stop offset="1" stop-color="#2c4f86" /></linearGradient></defs>
    <rect width="136" height="200" fill="url(#{uid}-g)" />
    <circle cx="106" cy="38" r="9" fill="#d9603a" />
    <path d="M68 54 C84 76 86 108 82 138 H54 C50 108 52 76 68 54Z" fill="#eef3fa" />
    <path d="M54 124 L38 152 H54Z M82 124 L98 152 H82Z" fill="#b9c6da" />
    <circle cx="68" cy="94" r="8" fill="#2c4f86" />
    <path d="M60 140 Q68 176 76 140Z" fill="#ffb020" />
    <circle cx="22" cy="60" r="1.6" fill="#fff" /><circle cx="118" cy="104" r="1.4" fill="#fff" /><circle cx="30" cy="150" r="1.2" fill="#fff" />
  {:else if art === 'redplanet'}
    <!-- Black with one crimson disc cut by its own shadow. -->
    <rect width="136" height="200" fill="#0d0508" />
    <circle cx="68" cy="100" r="54" fill="#c2261c" />
    <path d="M68 46 A54 54 0 0 1 68 154 A30 54 0 0 0 68 46Z" fill="#0d0508" opacity=".72" />
    <circle cx="46" cy="84" r="8" fill="#96190f" /><circle cx="52" cy="122" r="5" fill="#96190f" />
  {:else if art === 'dune'}
    <defs><linearGradient id="{uid}-g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6d9a0" /><stop offset=".5" stop-color="#e09a4a" /><stop offset="1" stop-color="#8a4a1c" /></linearGradient></defs>
    <rect width="136" height="200" fill="url(#{uid}-g)" />
    <circle cx="44" cy="46" r="13" fill="#fff4dc" /><circle cx="72" cy="30" r="6.5" fill="#fff4dc" opacity=".85" />
    <path d="M0 122 Q46 88 92 116 T136 100 V200 H0Z" fill="#b8692a" />
    <path d="M0 158 Q60 118 136 154 V200 H0Z" fill="#6e3814" />
    <path d="M28 146 Q62 126 98 146" fill="none" stroke="#3d1d09" stroke-width="6" stroke-linecap="round" />
  {:else if art === 'paddington'}
    <rect width="136" height="200" fill="#1f3f8f" />
    <circle cx="68" cy="60" r="74" fill="#2a52b5" />
    <rect x="38" y="74" width="60" height="76" rx="11" fill="#f2a024" />
    <rect x="45" y="82" width="9" height="60" rx="4.5" fill="#fff" opacity=".22" />
    <rect x="33" y="60" width="70" height="16" rx="5" fill="#fff6e6" />
    <rect x="48" y="100" width="40" height="24" rx="3" fill="#fff6e6" /><path d="M54 108 H82 M54 116 H74" stroke="#c96a12" stroke-width="2.4" />
  {:else if art === 'knives'}
    <!-- A whodunit in one shape: light through a keyhole. -->
    <rect width="136" height="200" fill="#12201a" />
    <circle cx="68" cy="92" r="56" fill="#1c3229" />
    <circle cx="68" cy="92" r="56" fill="none" stroke="#c9a24a" stroke-width="1.4" opacity=".7" />
    <path d="M68 56 a19 19 0 0 1 10 35.2 L86 132 H50 L58 91.2 A19 19 0 0 1 68 56Z" fill="#f0c15a" />
    <path d="M50 132 H86 L100 172 H36Z" fill="#f0c15a" opacity=".22" />
  {:else if art === 'robot'}
    <!-- One egg in a nest of leaves: what the machine finds. -->
    <rect width="136" height="200" fill="#1d4a32" />
    <path d="M-10 60 Q40 20 60 80 Q20 90 -10 60Z M146 40 Q96 30 92 90 Q130 90 146 40Z M-6 170 Q40 120 70 176 Q30 200 -6 170Z M142 176 Q110 124 76 170 Q110 204 142 176Z" fill="#2f7a4d" />
    <ellipse cx="68" cy="128" rx="44" ry="14" fill="#143524" />
    <path d="M68 70 C88 70 96 104 96 116 A28 24 0 0 1 40 116 C40 104 48 70 68 70Z" fill="#f1ead8" />
    <path d="M68 70 C88 70 96 104 96 116 A28 24 0 0 1 68 140 A40 44 0 0 0 68 70Z" fill="#000" opacity=".1" />
  {:else if art === 'conclave'}
    <!-- White smoke over a wall of red. -->
    <rect width="136" height="200" fill="#8f1420" />
    <rect y="126" width="136" height="74" fill="#5c0b14" />
    <rect x="58" y="96" width="20" height="40" fill="#2a0508" />
    <circle cx="68" cy="82" r="13" fill="#f6efe6" /><circle cx="82" cy="62" r="17" fill="#f6efe6" /><circle cx="60" cy="42" r="21" fill="#f6efe6" /><circle cx="86" cy="24" r="16" fill="#f6efe6" opacity=".85" />
  {:else}
    <!-- A lit doorway in a field at dusk. -->
    <defs><linearGradient id="{uid}-g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1a1440" /><stop offset=".6" stop-color="#7a2a4a" /><stop offset="1" stop-color="#e0703a" /></linearGradient></defs>
    <rect width="136" height="200" fill="url(#{uid}-g)" />
    <path d="M0 150 H136 V200 H0Z" fill="#140a14" />
    <path d="M30 150 V96 L68 70 L106 96 V150Z" fill="#1e1020" />
    <rect x="58" y="112" width="20" height="38" fill="#ffc45a" />
    <path d="M58 150 H78 L92 200 H44Z" fill="#ffc45a" opacity=".2" />
    <circle cx="104" cy="36" r="10" fill="#ffe7c2" />
  {/if}
</svg>

<style>
  .poster { display: block; width: 100%; height: 100%; }
</style>
