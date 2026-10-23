<!--
  Het Pleya-lockup uit de kop van de northstar (`.topnav .brand img`, 30 hoog;
  `.mhead img.wordmark`, 26 hoog) en boven het inlog- en setupformulier (36).

  Twee lagen, dezelfde splitsing als `PleyaWordmark` in de app: de P houdt zijn
  merkkleuren, en de belettering "LEYA" is een masker dat de kop met de inkt
  van het thema vult. Eén beeld met witte letters viel in het lichte thema weg
  tegen de pagina. Beide lagen komen uit `scripts/gen_brand_assets.py`.
-->
<script lang="ts">
  import { t } from '../i18n';

  let { size = 'nav' }: { size?: 'nav' | 'mobile' | 'form' } = $props();
</script>

<span
  class="wm"
  class:wm--mobile={size === 'mobile'}
  class:wm--form={size === 'form'}
  role="img"
  aria-label={t('app.name')}
>
  <img class="wm__mark" src="/brand/pleya-wordmark-mark.png" alt="" />
  <span class="wm__text" aria-hidden="true"></span>
</span>

<style>
  /* 138 bij 60 is de verhouding van het gegenereerde lockup. */
  .wm {
    position: relative;
    display: block;
    height: 30px;
    aspect-ratio: 138 / 60;
  }

  .wm--mobile {
    height: 26px;
  }

  .wm--form {
    height: 36px;
  }

  .wm__mark,
  .wm__text {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
  }

  .wm__text {
    background: var(--ink);
    mask: url('/brand/pleya-wordmark-text.png') center / 100% 100% no-repeat;
  }

  /* In forced colors valt een achtergrondkleur weg; de letters volgen dan de tekstkleur van het systeem. */
  @media (forced-colors: active) {
    .wm__text {
      forced-color-adjust: none;
      background: CanvasText;
    }
  }
</style>
