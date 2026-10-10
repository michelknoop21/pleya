<!--
  Het specimen v2 ("Pleya-server") nagebouwd met de echte componenten, als
  bewijs dat de primitieven samen een beheerscherm opleveren en niet alleen
  los kloppen. Leg de opname naast v2-specimen/v2@1600.png en v2@393.png; de
  zijbalk van het specimen hoort bij de app-schil en staat hier niet.
  Gallerijlabels zijn gewone Nederlandse tekst: de route bestaat alleen in
  ontwikkeling.
-->
<script lang="ts">
  import Alert from '$lib/components/Alert.svelte';
  import Panel from '$lib/components/Panel.svelte';
  import StatTile from '$lib/components/StatTile.svelte';
  import StatusPill from '$lib/components/StatusPill.svelte';
  import StorageMeter from '$lib/components/StorageMeter.svelte';
  import GallerySection from './GallerySection.svelte';
  import OverviewTable from './OverviewTable.svelte';
  import OverviewSide from './OverviewSide.svelte';
  import { LIBRARY_STORAGE, tb } from './overviewData';
</script>

<!-- Lijnicoon van 24 bij 24 zoals in het specimen; StatTile schaalt het naar 18. -->
{#snippet glyph(d: string)}
  <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round">
    <path {d} />
  </svg>
{/snippet}

<GallerySection id="overzicht" title="Overzicht">
  <div class="ov">
    <header class="ov__head">
      <div>
        <p class="ov__crumb">Serverbeheer</p>
        <h3 class="ov__title">Pleya-server</h3>
      </div>
      <StatusPill variant="dot" tone="ok" label="Online · versie 0.9.0 · 6 dagen actief" />
    </header>

    <Alert tone="warn" live={false}>
      <b>Opslagroot niet bereikbaar.</b>
      <span class="mono">/volume1/media/Boeken</span> is sinds 07:12 niet gemount. Boeken blijft zichtbaar
      met de laatst bekende inhoud.
      {#snippet actions()}
        <button type="button" class="btn btn--secondary btn--sm">Bekijk opslag</button>
      {/snippet}
    </Alert>

    <div class="ov__tiles">
      <StatTile label="Titels" value="1.284" sub="+12 deze week">
        {#snippet icon()}{@render glyph('M4 5h16v14H4zM8 5v14M16 5v14')}{/snippet}
        {#snippet spark()}
          <svg viewBox="0 0 100 40" preserveAspectRatio="none">
            <path
              d="M0 34 L15 30 L30 31 L45 22 L60 24 L75 14 L100 8 L100 40 L0 40Z"
              fill="currentColor"
              fill-opacity="0.12"
            />
            <path
              d="M0 34 L15 30 L30 31 L45 22 L60 24 L75 14 L100 8"
              fill="none"
              stroke="currentColor"
              stroke-width="1.6"
              vector-effect="non-scaling-stroke"
            />
          </svg>
        {/snippet}
      </StatTile>
      <StatTile label="Opslag" value="3,2" unit="TB vrij" sub="van 16 TB · 1 root niet gemount">
        {#snippet icon()}{@render glyph('M3 6h18v12H3zM7 12h.01')}{/snippet}
      </StatTile>
      <StatTile label="Scan" value="62" unit="%" sub="Series · 3.104 van 5.012">
        {#snippet icon()}{@render glyph('M3 12h4l3-8 4 16 3-8h4')}{/snippet}
      </StatTile>
      <StatTile label="Nu aan het kijken" value="2" sub="Apple TV woonkamer · iPhone">
        {#snippet icon()}{@render glyph('M7 4l13 8-13 8z')}{/snippet}
      </StatTile>
    </div>

    <Panel>
      {#snippet title()}Opslag per bibliotheek{/snippet}
      {#snippet actions()}<a class="ov__link" href="#opslagmeter">Alles bekijken</a>{/snippet}
      <StorageMeter label="Opslag per bibliotheek" segments={LIBRARY_STORAGE} format={tb} />
    </Panel>

    <OverviewTable />
    <OverviewSide />
  </div>
</GallerySection>


<style>
  .ov {
    display: flex;
    flex-direction: column;
    gap: 14px;
    max-width: 1280px;
  }

  .ov__head {
    display: flex;
    flex-wrap: wrap;
    align-items: flex-end;
    justify-content: space-between;
    gap: 8px var(--space-2);
    margin-bottom: 8px;
  }

  .ov__crumb {
    margin: 0 0 8px;
    font-size: 13px;
    color: var(--ink-3);
  }

  .ov__title {
    margin: 0;
    font-size: var(--text-page-title-size);
    font-weight: 800;
    line-height: 1.08;
    letter-spacing: -0.028em;
    color: var(--ink);
  }

  /* Vier tegels, twee onder 900; stretch houdt ze in een rij even hoog. */
  .ov__tiles {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    align-items: stretch;
    gap: 14px;
  }

  .ov__link {
    color: inherit;
    text-decoration: none;
  }

  .ov__link:hover {
    color: var(--ink);
  }

  @media (max-width: 1199px) {
    .ov__tiles {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (max-width: 899px) {
    .ov__title {
      font-size: 28px;
    }
  }
</style>
