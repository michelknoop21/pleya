<!--
  Een beheertabel (`.table` in web.css) in een flush Panel, zoals mockup 21,
  25 en 26 hem tekenen: kop in kleine hoofdletters, rijen van 12 px binnenrand,
  en een rechts uitgelijnde kolom voor acties.

  Onder 900 zijn er twee gedragingen. Standaard scrolt de tabel binnen het
  paneel (min. 640 breed), en dan is de scrollstrook een benoemde regio met
  een tabstop, zodat je hem ook met het toetsenbord kunt schuiven. Met `stack`
  wordt elke rij een kaart: eerste cel als titel, de overige eronder met hun
  kolomnaam (zichtbaar alleen met `showLabel`, anders voor de schermlezer), en
  de acties rechts; er scrolt dan niets, dus de tabstop vervalt. Dat is de web-afwijking uit web.css: een
  tabel met een actie per rij stapelt, anders staat de knop buiten beeld.

  De markup blijft een echte tabel met <th scope="col">, ook gestapeld; de
  kolomnaam in de kaart is daarom een gewone tekst in de cel en geen
  CSS-content, zodat een schermlezer hem leest als de tabelrol wegvalt.
-->
<script lang="ts" module>
  export interface Column {
    key: string;
    label: string;
    /** `end` is de rechterkolom: getallen of acties (`.r` in web.css). */
    align?: 'start' | 'end';
    /** Kop alleen voor een schermlezer, zoals de lege actiekop in de mockup. */
    hideLabel?: boolean;
    /**
     * Gestapeld de kolomnaam zichtbaar vóór de waarde. Standaard staat hij er
     * alleen voor een schermlezer: `.table.stack` en mockup 35@393 tonen kale
     * regels. Voor een waarde die zonder naam niets zegt, zoals een getal.
     */
    showLabel?: boolean;
  }
</script>

<script lang="ts" generics="T">
  import type { Snippet } from 'svelte';

  import { t } from '../i18n';
  import Panel from './Panel.svelte';

  interface Props {
    columns: Column[];
    rows: T[];
    /** Naam van de tabel (caption) en van de scrollstrook. */
    label: string;
    rowKey?: (row: T, index: number) => string | number;
    cell?: Snippet<[T, Column]>;
    empty?: Snippet;
    stack?: boolean;
    title?: Snippet;
    actions?: Snippet;
  }

  let {
    columns,
    rows,
    label,
    rowKey = (_row, index) => index,
    cell,
    empty,
    stack = false,
    title,
    actions
  }: Props = $props();

  // Zoveel cellen staan gestapeld links onder elkaar; de rechterkolom spant ze.
  const startCount = $derived(columns.filter((c) => c.align !== 'end').length);

  function plain(row: T, column: Column): string {
    const value = (row as Record<string, unknown>)[column.key];
    return value == null ? '' : String(value);
  }
</script>

<Panel flush {title} {actions}>
  {#if rows.length === 0}
    <div class="tbl__empty">
      {#if empty}{@render empty()}{:else}{t('table.empty')}{/if}
    </div>
  {:else}
    <!-- svelte-ignore a11y_no_noninteractive_tabindex -->
    <div
      class="tbl__scroll"
      class:tbl__scroll--stack={stack}
      role={stack ? undefined : 'region'}
      aria-label={stack ? undefined : label}
      tabindex={stack ? undefined : 0}
    >
      <table class="tbl" class:tbl--stack={stack} style:--tbl-rows={startCount}>
        <caption class="visually-hidden">{label}</caption>
        <thead>
          <tr>
            {#each columns as column (column.key)}
              <th scope="col" class:tbl__end={column.align === 'end'}>
                <span class:visually-hidden={column.hideLabel}>{column.label}</span>
              </th>
            {/each}
          </tr>
        </thead>
        <tbody>
          {#each rows as row, index (rowKey(row, index))}
            <tr>
              {#each columns as column, ci (column.key)}
                <td class:tbl__end={column.align === 'end'}>
                  {#if ci > 0 && column.align !== 'end' && !column.hideLabel}
                    <span class="tbl__label" class:visually-hidden={!column.showLabel}
                      >{column.label}</span
                    >
                  {/if}
                  {#if cell}{@render cell(row, column)}{:else}{plain(row, column)}{/if}
                </td>
              {/each}
            </tr>
          {/each}
        </tbody>
      </table>
    </div>
  {/if}
</Panel>

<style>
  .tbl {
    width: 100%;
    border-collapse: collapse;
    font-size: 14px;
  }

  th {
    padding: 8px 12px;
    /* rgba(255,255,255,.1) in de mockup: inkt op 10 procent, draait mee met het thema. */
    border-bottom: 1px solid color-mix(in srgb, var(--text) 10%, transparent);
    text-align: left;
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    white-space: nowrap;
    color: var(--ink-3);
  }

  td {
    padding: 12px;
    border-bottom: 1px solid color-mix(in srgb, var(--text) 6%, transparent);
    vertical-align: middle;
    color: var(--ink);
  }

  tbody tr:last-child td {
    border-bottom: 0;
  }

  .tbl__end {
    text-align: right;
  }

  .tbl__label {
    display: none;
  }

  .tbl__empty {
    padding: 24px 12px;
    font-size: 14px;
    color: var(--ink-3);
  }

  .tbl__scroll:focus-visible {
    outline: var(--ring) solid var(--ink);
    outline-offset: 2px;
    border-radius: var(--radius-md);
  }

  @media (hover: hover) {
    tbody tr:hover td {
      background: var(--fill);
    }
  }

  @media (max-width: 899px) {
    .tbl__scroll {
      overflow-x: auto;
    }

    .tbl {
      min-width: 640px;
    }

    .tbl__scroll--stack {
      overflow-x: visible;
    }

    .tbl--stack {
      display: block;
      min-width: 0;
    }

    .tbl--stack thead {
      display: none;
    }

    .tbl--stack tbody {
      display: block;
    }

    .tbl--stack tr {
      display: grid;
      grid-template-columns: 1fr auto;
      gap: 2px 10px;
      align-items: center;
      padding: 12px;
      border-bottom: 1px solid color-mix(in srgb, var(--text) 6%, transparent);
    }

    .tbl--stack tr:last-child {
      border-bottom: 0;
    }

    .tbl--stack td {
      display: block;
      padding: 0;
      border: 0;
      text-align: left;
    }

    .tbl--stack td:first-child {
      font-weight: 500;
    }

    .tbl--stack td:not(:first-child):not(.tbl__end) {
      grid-column: 1;
      font-size: 13px;
      color: var(--ink-3);
    }

    .tbl--stack td.tbl__end {
      grid-column: 2;
      grid-row: 1 / span var(--tbl-rows);
    }

    .tbl--stack .tbl__label {
      display: inline;
      margin-right: 6px;
      color: var(--ink-4);
    }
  }
</style>
