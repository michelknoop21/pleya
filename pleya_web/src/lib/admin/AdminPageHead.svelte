<!--
  De kop van een beheerscherm (21, 22): kruimelpad, de h1 en rechts de acties.
  De kruimels zijn links behalve de laatste, die is de pagina zelf. Onder 900
  zakken de acties onder de titel, zoals 21@393 en 22@393 ze tekenen.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';

  import { t } from '../i18n';

  interface Crumb {
    label: string;
    href?: string;
  }

  interface Props {
    title: string;
    crumbs: Crumb[];
    actions?: Snippet;
  }

  let { title, crumbs, actions }: Props = $props();
</script>

<header class="head">
  <nav class="crumb" aria-label={t('admin.lib.crumbs')}>
    <ol>
      {#each crumbs as crumb, i (i)}
        <li>
          {#if crumb.href}<a href={crumb.href}>{crumb.label}</a>{:else}<span aria-current="page"
              >{crumb.label}</span
            >{/if}
        </li>
      {/each}
    </ol>
  </nav>
  <div class="row">
    <h1 class="title">{title}</h1>
    {#if actions}
      <div class="actions">{@render actions()}</div>
    {/if}
  </div>
</header>

<style>
  .head {
    margin-bottom: 18px;
  }

  .crumb ol {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    margin: 0 0 4px;
    padding: 0;
    list-style: none;
    font-size: 13px;
    color: var(--ink-3);
  }

  /* Het driehoekje uit de northstar (▸). Als rand getekend en niet als teken:
     de gebundelde Inter heeft de glyph niet en viel terug op een punt. */
  .crumb li + li::before {
    content: '';
    display: inline-block;
    margin: 0 6px 0 2px;
    border-block: 3.5px solid transparent;
    border-left: 4px solid currentColor;
    vertical-align: 1px;
  }

  .crumb a {
    color: inherit;
  }

  @media (hover: hover) {
    .crumb a:hover {
      color: var(--ink);
    }
  }

  .row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 12px 16px;
  }

  .title {
    min-width: 0;
    margin: 0;
    font-size: 34px;
    font-weight: 700;
    line-height: 1.1;
    letter-spacing: -0.01em;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }

  @media (max-width: 899px) {
    .title {
      font-size: 26px;
    }

    .row {
      flex-direction: column;
      align-items: stretch;
    }
  }
</style>
