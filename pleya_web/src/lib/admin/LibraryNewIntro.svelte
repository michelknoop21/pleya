<!--
  Bibliotheek toevoegen, stap 1 en 2: wat erin staat (de soort als tegels) en
  de naam. Bij bewerken blijft LibrarySettingsPanel het paneel.

  Uit het doelbeeld niet gebouwd, omdat `CreateLibraryRequest` het niet draagt:
  taal voor titels en samenvattingen, land voor de kijkwijzer, en Boeken als
  soort (`LibraryKind` kent alleen `movies` en `shows`).
-->
<script lang="ts">
  import Choice, { type ChoiceOption } from '../components/Choice.svelte';
  import Field from '../components/Field.svelte';
  import Panel from '../components/Panel.svelte';
  import { t } from '../i18n';
  import { LIBRARY_KINDS, kindLabel, type LibraryForm } from './libraries';
  import StepTitle from './StepTitle.svelte';

  let { form = $bindable() }: { form: LibraryForm } = $props();

  const kindOptions: ChoiceOption[] = LIBRARY_KINDS.map((kind) => ({
    value: kind,
    label: kindLabel(kind),
    description: t(kind === 'movies' ? 'admin.lib.kind.moviesHint' : 'admin.lib.kind.showsHint')
  }));
</script>

<Panel>
  {#snippet title()}<StepTitle n={1}>{t('admin.lib.step.kind')}</StepTitle>{/snippet}
  <Choice
    legend={t('admin.lib.form.kind')}
    hideLegend
    layout="grid"
    columns={2}
    options={kindOptions}
    bind:value={form.kind}
    hint={t('admin.lib.form.kindLocked')}
  />
</Panel>

<Panel>
  {#snippet title()}<StepTitle n={2}>{t('admin.lib.form.name')}</StepTitle>{/snippet}
  <div class="name">
    <Field label={t('admin.lib.form.name')} hideLabel bind:value={form.title} required autocomplete="off" />
  </div>
</Panel>

<style>
  .name {
    max-width: 560px;
  }
</style>
