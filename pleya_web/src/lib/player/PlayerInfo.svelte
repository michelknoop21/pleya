<!--
  Afspeelinfo uit het doelbeeld Kijken-speler: wat er nu geleverd wordt. Alleen
  regels waar een bron voor is: het plan, de versie en het `<video>`-element.
  Bitrate en het soort verbinding staan er niet; het contract draagt ze niet.
-->
<script lang="ts">
  import { t } from '../i18n';

  let { rows }: { rows: [label: string, value: string][] } = $props();
</script>

<aside class="info" aria-label={t('player.info')}>
  <h2 class="info__title">{t('player.info')}</h2>
  <dl class="info__list">
    {#each rows as [label, value] (label)}
      <dt>{label}</dt>
      <dd>{value}</dd>
    {/each}
  </dl>
</aside>

<style>
  .info {
    position: absolute;
    top: calc(96px + env(safe-area-inset-top, 0px));
    left: var(--player-inset);
    width: min(360px, calc(100% - 2 * var(--player-inset)));
    padding: 16px;
    border-radius: var(--radius-card);
    border: 1px solid rgba(255, 255, 255, 0.14);
    background: rgba(20, 20, 20, 0.94);
    pointer-events: none;
  }

  .info__title {
    margin: 0 0 10px;
    font-size: var(--text-caps-size);
    font-weight: 400;
    letter-spacing: var(--text-caps-track);
    text-transform: uppercase;
    color: rgba(255, 255, 255, 0.7);
  }

  .info__list {
    display: grid;
    grid-template-columns: 108px minmax(0, 1fr);
    gap: 5px 12px;
    margin: 0;
    font-size: 12.5px;
  }

  .info__list dt {
    color: rgba(255, 255, 255, 0.7);
  }

  .info__list dd {
    margin: 0;
    overflow-wrap: anywhere;
  }

  @media (max-width: 899px) {
    .info {
      top: calc(72px + env(safe-area-inset-top, 0px));
    }
  }
</style>
