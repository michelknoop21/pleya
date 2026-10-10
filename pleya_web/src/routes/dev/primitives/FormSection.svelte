<!-- Gallerijlabels zijn hier gewone Nederlandse tekst: de route bestaat alleen in ontwikkeling. -->
<script lang="ts">
  import Field from '$lib/components/Field.svelte';
  import Select from '$lib/components/Select.svelte';
  import Toggle from '$lib/components/Toggle.svelte';
  import Choice from '$lib/components/Choice.svelte';
  import GallerySection from './GallerySection.svelte';

  const roles = [
    { value: 'viewer', label: 'Kijker' },
    { value: 'admin', label: 'Beheerder' },
    { value: 'owner', label: 'Eigenaar', disabled: true }
  ];

  const kinds = [
    { value: 'movies', label: 'Films', description: 'Losse titels met één bestand' },
    { value: 'shows', label: 'Series', description: 'Seizoenen en afleveringen' },
    { value: 'books', label: 'Boeken', description: 'EPUB en PDF', disabled: true }
  ];

  let name = $state('Films');
  let role = $state('admin');
  let kind = $state('shows');
  let tile = $state('movies');
  let on = $state(true);
  let off = $state(false);
</script>

<GallerySection id="velden" title="Velden">
  <div class="gs__grid">
    <Field label="Naam" bind:value={name} />
    <Field
      id="veld-hint"
      label="Pad"
      placeholder="/media/films"
      hint="Het pad zoals de server het ziet, niet zoals jouw computer het ziet."
    />
    <Field label="Poort" value="80800" error="Een poort ligt tussen 1 en 65535." />
    <Field id="veld-fout-focus" label="Poort (fout, focus)" value="0" error="Een poort ligt tussen 1 en 65535." />
    <Field label="Server-id" value="pleya-nas-01" disabled />
  </div>

  <div class="gs__grid">
    <Select label="Rol" options={roles} bind:value={role} />
    <Select
      label="Taal"
      options={[{ value: 'nl', label: 'Nederlands' }]}
      placeholder="Kies een taal"
      error="Kies een taal."
    />
    <Select label="Rol (vast)" options={roles} value="viewer" disabled />
  </div>

  <div class="gs__grid">
    <Toggle label="Automatisch scannen" description="Nieuwe bestanden binnen een minuut." bind:checked={on} />
    <Toggle label="Ondertitels downloaden" bind:checked={off} />
    <Toggle label="Transcoderen" description="Komt in PS-8." checked disabled />
  </div>

  <div class="gs__grid">
    <Choice legend="Soort bibliotheek" options={kinds} bind:value={kind} hint="Bepaalt hoe de scanner bestanden leest." />
    <Choice legend="Soort (fout)" options={kinds.slice(0, 2)} error="Kies een soort." />
  </div>

  <Choice legend="Soort bibliotheek als tegels" options={kinds} layout="grid" bind:value={tile}>
    {#snippet icon(option)}
      <svg viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
        {#if option.value === 'books'}
          <path d="M5 4h10a3 3 0 0 1 3 3v13H8a3 3 0 0 1-3-3z" fill="none" stroke="currentColor" stroke-width="1.8" />
        {:else}
          <rect x="3" y="5" width="18" height="14" rx="2" fill="none" stroke="currentColor" stroke-width="1.8" />
        {/if}
      </svg>
    {/snippet}
  </Choice>
</GallerySection>
