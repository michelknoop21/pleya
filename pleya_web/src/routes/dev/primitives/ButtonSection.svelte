<!--
  De knoppen met de langste labels uit de catalogus, in de taal van de pagina.
  Twee vormen: los naast elkaar zoals in een formulier, en twee aan twee op
  gelijke breedte zoals de hero en de dialoog ze onder 900 zetten. Daar zit het
  risico: "Eigenaar aanmaken" naast "Annuleren" op 393 is smaller dan het
  Engelse "Create owner". Een knop breekt nooit (`.btn` is nowrap) en houdt
  zijn raakvlak van --button-height; de opname laat zien of hij dan nog past.

  Galerijlabels zijn gewone Nederlandse tekst: de route bestaat alleen in
  ontwikkeling. De knoplabels zelf komen via t(), anders bewijst de opname in
  twee talen niets.
-->
<script lang="ts">
  import { t } from '#lib/i18n/index.js';
  import GallerySection from './GallerySection.svelte';

  const labels = [
    t('common.retry'),
    t('setup.submit'),
    t('rail.viewAll'),
    t('login.submit'),
    t('hero.play'),
    t('hero.moreInfo')
  ];
</script>

<GallerySection id="knoppen" title="Knoppen">
  <p class="gs__caption">los naast elkaar</p>
  <div class="bs__row">
    {#each labels as label (label)}
      <button type="button" class="btn btn--secondary">{label}</button>
    {/each}
  </div>
  <p class="gs__caption">twee aan twee op gelijke breedte, zoals hero en dialoog onder 900</p>
  <div class="bs__pair">
    <button type="button" class="btn btn--quiet">{t('common.cancel')}</button>
    <button type="button" class="btn">{t('setup.submit')}</button>
  </div>
  <div class="bs__pair">
    <button type="button" class="btn">{t('common.retry')}</button>
    <button type="button" class="btn btn--secondary">{t('rail.viewAll')}</button>
  </div>
</GallerySection>

<style>
  .bs__row {
    display: flex;
    flex-wrap: wrap;
    gap: var(--space-half);
  }

  .bs__pair {
    display: flex;
    gap: var(--space-half);
    /* 393 min twee keer de inzet van 16: de breedte van een telefoonkolom. */
    max-width: 361px;
  }

  .bs__pair .btn {
    flex: 1 1 0;
    min-width: 0;
  }
</style>
