<!--
  Een melding in de pagina (`.alert` in web.css): icoon, tekst en rechts een
  optionele actie. Amber is de standaard (iets vraagt aandacht, mockup 20),
  `err` is rood voor wat stuk is, `info` is neutraal (mockup 21). Onder 900
  zakt de actie naar een eigen regel, ingesprongen tot onder de tekst.

  De rol volgt de toon: een fout is role="alert" en onderbreekt de
  schermlezer, een waarschuwing en een toelichting zijn role="status" en
  wachten hun beurt af. Een melding die al bij het laden vaststaat en niet
  verandert kan `live={false}` krijgen, dan is het gewoon tekst.

  Designsysteem v2: de melding staat op het paneelvlak met een vleug van de
  toonkleur erover (7 procent), zodat hij in elk thema dezelfde diepte heeft
  als de panelen eromheen; de tekst is gedimde inkt, de titel volle inkt.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    tone?: 'warn' | 'err' | 'info';
    title?: string;
    children: Snippet;
    actions?: Snippet;
    live?: boolean;
  }

  let { tone = 'warn', title, children, actions, live = true }: Props = $props();

  const role = $derived(live ? (tone === 'err' ? 'alert' : 'status') : undefined);
</script>

<div class="alert alert--{tone}" {role}>
  <svg
    class="alert__icon"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
    focusable="false"
  >
    <!-- Dezelfde glyphs als `alert` en `info` in de northstar (build.mjs). -->
    {#if tone === 'info'}
      <circle cx="12" cy="12" r="9" />
      <path d="M12 11v6M12 7.5v.5" />
    {:else}
      <path d="M12 3 2 20h20z" />
      <path d="M12 10v4M12 17v.5" />
    {/if}
  </svg>
  <div class="alert__body">
    {#if title}<b class="alert__title">{title}</b>{' '}{/if}
    {@render children()}
  </div>
  {#if actions}
    <div class="alert__actions">{@render actions()}</div>
  {/if}
</div>

<style>
  .alert {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 14px 16px;
    border: 1px solid color-mix(in srgb, var(--amber) 34%, transparent);
    border-radius: var(--radius-md);
    background: color-mix(in srgb, var(--amber) 7%, var(--panel));
    font-size: 14px;
    line-height: 1.45;
    color: var(--ink-2);
  }

  .alert__icon {
    flex: none;
    width: 18px;
    height: 18px;
    color: var(--warn-ink);
  }

  .alert--err {
    border-color: color-mix(in srgb, var(--danger-ink) 34%, transparent);
    background: color-mix(in srgb, var(--danger-ink) 7%, var(--panel));
  }

  .alert--err .alert__icon {
    color: var(--danger-ink);
  }

  .alert--info {
    border-color: var(--hairline-strong);
    background: var(--panel);
  }

  .alert--info .alert__icon {
    color: var(--ink-2);
  }

  .alert__body {
    flex: 1 1 auto;
    min-width: 0;
  }

  .alert__title {
    font-weight: 600;
    color: var(--ink);
  }

  .alert__actions {
    flex: none;
    display: flex;
    align-items: center;
    gap: 8px;
    margin-left: auto;
  }

  @media (max-width: 899px) {
    .alert {
      flex-wrap: wrap;
    }

    .alert {
      align-items: flex-start;
    }

    .alert__body {
      flex-basis: calc(100% - 32px);
    }

    .alert__icon {
      margin-top: 2px;
    }

    /* 32 = icoon 18 plus gat 14: de actie lijnt uit met de tekst. */
    .alert__actions {
      margin-left: 32px;
    }
  }
</style>
