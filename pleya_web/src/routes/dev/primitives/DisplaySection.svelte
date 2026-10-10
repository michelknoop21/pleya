<!-- Gallerijlabels zijn hier gewone Nederlandse tekst: de route bestaat alleen in ontwikkeling. -->
<script lang="ts">
  import Panel from '$lib/components/Panel.svelte';
  import StatTile from '$lib/components/StatTile.svelte';
  import StatusPill, { type PillTone } from '$lib/components/StatusPill.svelte';
  import Alert from '$lib/components/Alert.svelte';
  import Chips from '$lib/components/Chips.svelte';
  import GallerySection from './GallerySection.svelte';

  const tones: { tone: PillTone; label: string }[] = [
    { tone: 'ok', label: 'Online' },
    { tone: 'warn', label: 'Bijna vol' },
    { tone: 'err', label: 'Mislukt' },
    { tone: 'run', label: 'Scant' },
    { tone: 'idle', label: 'Gepland' }
  ];

  const genres = [
    { id: 'all', label: 'Alles', count: 412 },
    { id: 'drama', label: 'Drama', count: 96 },
    { id: 'comedy', label: 'Komedie', count: 71 },
    { id: 'docu', label: 'Documentaire' },
    { id: 'scifi', label: 'Sciencefiction', count: 23 }
  ];

  let single = $state(['all']);
  let multiple = $state(['drama', 'scifi']);
  let quiet = $state(['comedy']);
</script>

<GallerySection id="panelen" title="Panelen en tegels">
  <div class="gs__grid">
    <Panel>
      {#snippet title()}Opslag{/snippet}
      {#snippet actions()}
        <button type="button" class="btn btn--secondary btn--sm">Bewerken</button>
      {/snippet}
      <p class="t-body">Een paneel met titel en acties, standaard binnenrand.</p>
    </Panel>
    <Panel flush>
      {#snippet title()}Flush paneel{/snippet}
      {#snippet actions()}
        <button type="button" class="btn btn--ghost btn--sm">Alles</button>
      {/snippet}
      <p class="t-body">Flush: smalle binnenrand, voor een tabel of lijst.</p>
    </Panel>
    <Panel tone="warn">
      {#snippet title()}Onderhoudsmodus{/snippet}
      <p class="t-body">Weigert nieuwe streams en scans; lopende sessies blijven geldig.</p>
      <button type="button" class="btn btn--ghost btn--sm">Onderhoudsmodus aan</button>
    </Panel>
    <Panel tone="danger">
      {#snippet title()}Gevarenzone{/snippet}
      <p class="t-body">Bibliotheek verwijderen haalt alle kijkstatus weg.</p>
      <button type="button" class="btn btn--danger btn--sm">Verwijderen</button>
    </Panel>
  </div>

  <div class="gs__grid">
    <StatTile label="Titels" value="1.284" sub="+12 deze week" />
    <StatTile label="Opslag" value="3,4 TB" sub="van 8 TB" />
    <StatTile label="Actieve sessies" value="2" />
    <StatTile label="Laatste scan" value="09:41">
      {#snippet icon()}
        <svg viewBox="0 0 24 24" width="18" height="18" aria-hidden="true">
          <circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" stroke-width="1.8" />
          <path d="M12 8v4l3 2" fill="none" stroke="currentColor" stroke-width="1.8" />
        </svg>
      {/snippet}
    </StatTile>
  </div>
</GallerySection>

<GallerySection id="pillen" title="Statuspillen">
  <div>
    <p class="gs__caption">Standaard</p>
    <div class="gs__row">
      {#each tones as item (item.tone)}<StatusPill tone={item.tone} label={item.label} />{/each}
    </div>
  </div>
  <div>
    <p class="gs__caption">Met stip</p>
    <div class="gs__row">
      {#each tones as item (item.tone)}<StatusPill tone={item.tone} label={item.label} dot />{/each}
    </div>
  </div>
  <div>
    <p class="gs__caption">Klein</p>
    <div class="gs__row">
      {#each tones as item (item.tone)}<StatusPill tone={item.tone} label={item.label} size="sm" />{/each}
    </div>
  </div>
</GallerySection>

<GallerySection id="meldingen" title="Meldingen">
  <div class="gs__stack">
    <Alert tone="warn" title="Schijf bijna vol" live={false}>Nog 120 GB vrij op /volume1.</Alert>
    <Alert tone="err" title="Scan mislukt" live={false}>
      De map /media/films is niet leesbaar.
      {#snippet actions()}
        <button type="button" class="btn btn--secondary btn--sm">Opnieuw</button>
      {/snippet}
    </Alert>
    <Alert tone="info" live={false}>Een melding zonder titel en zonder acties.</Alert>
    <Alert tone="info" title="Nieuwe versie" live={false}>
      Pleya Server 0.9 staat klaar.
      {#snippet actions()}
        <button type="button" class="btn btn--sm">Bijwerken</button>
        <button type="button" class="btn btn--ghost btn--sm">Later</button>
      {/snippet}
    </Alert>
  </div>
</GallerySection>

<GallerySection id="chips" title="Chips">
  <div>
    <p class="gs__caption">Eén keuze, outline</p>
    <Chips label="Genre" options={genres} bind:selected={single} />
  </div>
  <div>
    <p class="gs__caption">Meerdere keuzes, outline</p>
    <Chips label="Genres" options={genres} multiple bind:selected={multiple} />
  </div>
  <div>
    <p class="gs__caption">Quiet</p>
    <Chips label="Genre (quiet)" options={genres} variant="quiet" bind:selected={quiet} />
  </div>
</GallerySection>
