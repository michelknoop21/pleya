<!-- Gallerijlabels zijn hier gewone Nederlandse tekst: de route bestaat alleen in ontwikkeling. -->
<script lang="ts">
  import Panel from '$lib/components/Panel.svelte';
  import StorageMeter, { type MeterSegment } from '$lib/components/StorageMeter.svelte';
  import GallerySection from './GallerySection.svelte';
  import { LIBRARY_STORAGE, tb } from './overviewData';

  // Bijna vol: Kids in het merkrood en nog 0,3 TB vrij van 16 TB.
  const nearlyFull: MeterSegment[] = [
    { label: 'Films', value: 9.1, tone: 'ink' },
    { label: 'Series', value: 4.6, tone: 'amber' },
    { label: 'Kids', value: 1.6, tone: 'red' },
    { label: 'Boeken', value: 0.4, tone: 'blue' },
    { label: 'Vrij', value: 0.3, tone: 'free' }
  ];

  // Onbekend: de opslagroot is niet gemount, dus er is niets te meten.
  const unknown: MeterSegment[] = [];
</script>

<GallerySection id="opslagmeter" title="Opslagmeter">
  <div class="gs__stack">
    <Panel>
      {#snippet title()}Normaal{/snippet}
      {#snippet actions()}<span class="tnum">12,8 van 16 TB</span>{/snippet}
      <StorageMeter label="Opslag per bibliotheek" segments={LIBRARY_STORAGE} format={tb} />
    </Panel>
    <Panel>
      {#snippet title()}Bijna vol{/snippet}
      {#snippet actions()}<span class="tnum">15,7 van 16 TB</span>{/snippet}
      <StorageMeter label="Opslag per bibliotheek, bijna vol" segments={nearlyFull} format={tb} />
    </Panel>
    <Panel>
      {#snippet title()}Leeg of onbekend{/snippet}
      <StorageMeter label="Opslag per bibliotheek, onbekend" segments={unknown}>
        {#snippet empty()}
          Geen meting: <span class="mono">/volume1/media</span> is niet gemount.
        {/snippet}
      </StorageMeter>
    </Panel>
  </div>
</GallerySection>

<style>
  .tnum {
    font-variant-numeric: tabular-nums;
  }
</style>
