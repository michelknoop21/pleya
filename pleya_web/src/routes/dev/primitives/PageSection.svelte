<!--
  Paginakop en lege staat in één sectie, zodat de gate ze samen naast 13 kan
  leggen: bovenaan de kop in drie vormen (kaal, met aantal, met actie), daaronder
  13 nagebouwd (kop "Boeken" boven de lege staat met eigen icoon en twee
  uitwegen), en de fout met herhaalknop en de compacte staat binnen een sectie.

  Elke PageHeader zet hier een h1 naast die van de galerij. Op een echte route
  is er één; de galerij toont alleen hoe hij eruitziet.

  Galerijlabels en voorbeeldteksten zijn gewone Nederlandse tekst: de route
  bestaat alleen in ontwikkeling.
-->
<script lang="ts">
  import PageHeader from '$lib/components/PageHeader.svelte';
  import StateView from '$lib/components/StateView.svelte';
  import GallerySection from './GallerySection.svelte';
</script>

{#snippet bookIcon()}
  <svg
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="2"
    stroke-linecap="round"
    stroke-linejoin="round"
  >
    <path d="M3 5.5C5.5 4.5 8.5 4.5 11 6v13.5c-2.5-1.5-5.5-1.5-8-.5zM13 6c2.5-1.5 5.5-1.5 8-.5V19c-2.5-1-5.5-1-8 .5z" />
  </svg>
{/snippet}

<GallerySection id="paginabouw" title="Paginakop en staat">
  <p class="gs__caption">paginakop: kaal, met aantal, met actie</p>
  <div class="pb__frame">
    <PageHeader title="Bibliotheken" />
  </div>
  <div class="pb__frame">
    <PageHeader title="Alle films" sub={461} />
  </div>
  <div class="pb__frame">
    <PageHeader title="Verzamelingen">
      {#snippet actions()}
        <button type="button" class="btn btn--sm">Nieuwe verzameling</button>
      {/snippet}
    </PageHeader>
  </div>

  <p class="gs__caption">lege bibliotheek, zoals 13</p>
  <div class="pb__frame" data-shot="leeg">
    <PageHeader title="Boeken" />
    <StateView
      title="Nog geen boeken"
      message="De bibliotheek Boeken is aangemaakt maar de eerste scan heeft nog niets gevonden. Pleya zoekt naar EPUB-bestanden in /volume1/media/Boeken."
      icon={bookIcon}
    >
      {#snippet actions()}
        <button type="button" class="btn btn--sm">Nu scannen</button>
        <button type="button" class="btn btn--ghost btn--sm">Bibliotheek bekijken in Serverbeheer</button>
      {/snippet}
      Zie je deze pagina als gebruiker zonder beheerrecht, dan staan hier alleen de eerste twee regels
      en geen knoppen.
    </StateView>
  </div>

  <p class="gs__caption">fout met herhaalknop, en compact binnen een sectie</p>
  <div class="gs__grid">
    <div class="pb__frame">
      <StateView kind="error" message="De server antwoordde niet binnen tien seconden." onRetry={() => {}} />
    </div>
    <div class="pb__frame">
      <StateView compact title="Nog geen afleveringen" />
    </div>
  </div>
</GallerySection>

<style>
  /* Een eigen vlak per voorbeeld, met de paginainzet erin zoals .page hem geeft. */
  .pb__frame {
    padding: 0 var(--inset);
    border: 1px solid var(--hairline);
    border-radius: var(--radius-card);
  }
</style>
