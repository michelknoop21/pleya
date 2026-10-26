<!--
  De zoekbalk uit mockup 50: rood tot de afspeelpositie, lichter tot waar
  gebufferd is, een witte knop. Onder de motorkap een gewone
  `<input type="range">`, zodat toetsenbord en schermlezer hem zonder extra
  code bedienen.

  Hoofdstukmarkeringen en het scrubvoorbeeld uit de mockup ontbreken: het
  contract draagt geen hoofdstukken en geen voorbeeldbeelden. Bij een
  omzetsessie (`limit`) kan alleen gezocht worden in wat er al omgezet is.
-->
<script lang="ts">
  import { t } from '../i18n';
  import { clamp, formatPlayTime } from './keyboard';

  interface Props {
    current: number;
    total: number;
    buffered: number;
    /** Verste zoekbare punt bij een omzetsessie; null bij direct play. */
    limit: number | null;
    onseek: (seconds: number) => void;
  }

  let { current, total, buffered, limit, onseek }: Props = $props();

  const max = $derived(total > 0 ? total : 0);
  const pct = (v: number) => (max > 0 ? `${clamp((v / max) * 100, 0, 100)}%` : '0%');

  function seek(event: Event): void {
    const value = Number((event.currentTarget as HTMLInputElement).value);
    onseek(limit === null ? value : Math.min(value, limit));
  }
</script>

<div class="seek">
  <div class="seek__track" aria-hidden="true">
    <span class="seek__buffer" style:width={pct(buffered)}></span>
    <span class="seek__played" style:width={pct(current)}></span>
    <span class="seek__thumb" style:left={pct(current)}></span>
  </div>
  <input
    class="seek__input"
    type="range"
    min="0"
    max={max}
    step="1"
    value={Math.floor(current)}
    disabled={max === 0}
    aria-label={t('player.seek')}
    aria-valuetext={t('player.seekValue', {
      time: formatPlayTime(current),
      total: formatPlayTime(max)
    })}
    title={limit !== null ? t('player.notSeekable') : undefined}
    oninput={seek}
  />
</div>

<style>
  .seek {
    position: relative;
    height: 24px;
    display: flex;
    align-items: center;
  }

  .seek__track {
    position: absolute;
    inset: 10px 0;
    border-radius: 2px;
    /* web: de speler is altijd donker, net als op TV; wit op beeld. */
    background: rgba(255, 255, 255, 0.28);
    pointer-events: none;
  }

  .seek__buffer,
  .seek__played {
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    border-radius: 2px;
  }

  .seek__buffer {
    background: rgba(255, 255, 255, 0.55);
  }

  .seek__played {
    background: var(--accent);
  }

  .seek__thumb {
    position: absolute;
    top: 50%;
    width: 16px;
    height: 16px;
    margin: -8px 0 0 -8px;
    border-radius: 50%;
    background: #fff;
    transition: transform var(--dur-fast) var(--ease);
  }

  .seek__input {
    position: relative;
    width: 100%;
    height: 24px;
    margin: 0;
    opacity: 0;
    cursor: pointer;
  }

  .seek__input:disabled {
    cursor: default;
  }

  /* De echte input is onzichtbaar; zijn focus komt op de knop terecht. */
  .seek:has(.seek__input:focus-visible) .seek__thumb {
    outline: var(--ring) solid #fff;
    outline-offset: 3px;
    transform: scale(1.15);
  }
</style>
