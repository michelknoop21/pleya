<!--
  De onderste rij van specimen v2: links het formulierpaneel (naam met focus,
  pad in mono met hulptekst, poort met fout, twee schakelaars), rechts de
  gevarenzone en een paneel dat nog laadt. Onder 900 onder elkaar.
  Gallerijlabels zijn gewone Nederlandse tekst: de route bestaat alleen in
  ontwikkeling.
-->
<script lang="ts">
  import Field from '$lib/components/Field.svelte';
  import Panel from '$lib/components/Panel.svelte';
  import Skeleton from '$lib/components/Skeleton.svelte';
  import Toggle from '$lib/components/Toggle.svelte';

  let name = $state('Films');
  let path = $state('/volume1/media/Films');
  let autoScan = $state(true);
  let transcode = $state(false);
</script>

<div class="os">
  <Panel>
    {#snippet title()}Bibliotheek bewerken{/snippet}
    <div class="os__form">
      <Field label="Naam" bind:value={name} />
      <Field label="Pad" mono bind:value={path} hint="Het pad staat op de server, niet op dit toestel." />
      <Field label="Poort" mono value="80800" error="Kies een poort tussen 1 en 65535." />
      <Toggle label="Automatisch scannen" description="Nieuwe bestanden binnen een minuut" bind:checked={autoScan} />
      <Toggle label="Transcoderen" description="Alleen als direct play niet kan" bind:checked={transcode} />
    </div>
  </Panel>

  <div class="os__col">
    <Panel tone="danger">
      {#snippet title()}Gevarenzone{/snippet}
      {#snippet actions()}
        <button type="button" class="btn btn--danger btn--sm">Verwijderen</button>
      {/snippet}
      <p class="os__note">Verwijderen haalt alle kijkstatus weg.</p>
    </Panel>

    <Panel>
      <div class="os__media">
        <Skeleton kind="block" />
        <div class="os__lines">
          <Skeleton kind="line" width="70%" />
          <Skeleton kind="line" width="92%" />
          <Skeleton kind="line" width="48%" />
        </div>
      </div>
    </Panel>
  </div>
</div>

<style>
  .os {
    display: grid;
    grid-template-columns: minmax(0, 1.2fr) minmax(0, 1fr);
    align-items: start;
    gap: 14px;
  }

  .os__form {
    display: grid;
    gap: 16px;
  }

  .os__col {
    display: grid;
    align-content: start;
    gap: 14px;
  }

  .os__note {
    margin: 0;
    font-size: 13px;
    color: var(--ink-3);
  }

  /* Specimen v2: poster van 64 breed in 2:3 met drie regels ernaast. */
  .os__media {
    display: grid;
    grid-template-columns: 64px 1fr;
    gap: 14px;
  }

  .os__media > :global(.skel) {
    aspect-ratio: var(--aspect-poster);
  }

  .os__lines {
    display: grid;
    align-content: center;
    gap: 10px;
  }

  @media (max-width: 899px) {
    .os {
      grid-template-columns: minmax(0, 1fr);
    }
  }
</style>
