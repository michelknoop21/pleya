<!--
  Het paneel Instellingen van scherm 22: naam, soort, scaninterval en scannen
  bij het opstarten. De soort ligt vast zodra er inhoud is (PS-14 beslissing 4,
  `library.not_empty`): dan is alleen de huidige soort te kiezen.

  De northstar zet interval en opstarten in één keuzelijst ("Elke 6 uur, en bij
  het opstarten"). Het contract draagt twee losse velden, dus hier staan ze
  apart: een keuzelijst en een schakelaar.

  Boeken staat niet tussen de soorten: `LibraryKind` kent alleen `movies` en
  `shows`, tot PS-14 vrijgegeven is.
-->
<script lang="ts">
  import Choice, { type ChoiceOption } from '../components/Choice.svelte';
  import Field from '../components/Field.svelte';
  import Panel from '../components/Panel.svelte';
  import Select from '../components/Select.svelte';
  import Toggle from '../components/Toggle.svelte';
  import { t } from '../i18n';
  import {
    LIBRARY_KINDS,
    intervalOptions,
    kindHint,
    kindLabel,
    type LibraryForm
  } from './libraries';

  interface Props {
    form: LibraryForm;
    /** De soort die de server nu kent; null bij een nieuwe bibliotheek. */
    currentKind: string | null;
    itemCount: number;
    readonly?: boolean;
    titleError?: string;
  }

  let {
    form = $bindable(),
    currentKind,
    itemCount,
    readonly = false,
    titleError
  }: Props = $props();

  const kindOptions: ChoiceOption[] = $derived(
    LIBRARY_KINDS.map((kind) => ({
      value: kind,
      label: kindLabel(kind),
      disabled: itemCount > 0 && currentKind !== null && kind !== currentKind
    }))
  );
</script>

<Panel>
  {#snippet title()}{t('admin.lib.form.settings')}{/snippet}
  <div class="form">
    <Field
      label={t('admin.lib.form.name')}
      bind:value={form.title}
      disabled={readonly}
      required
      error={titleError}
      autocomplete="off"
    />
    <Choice
      legend={t('admin.lib.form.kind')}
      options={kindOptions}
      bind:value={form.kind}
      disabled={readonly}
      hint={currentKind === null ? undefined : t(kindHint(itemCount))}
    />
    <Select
      label={t('admin.lib.form.interval')}
      options={intervalOptions(form.interval)}
      bind:value={form.interval}
      disabled={readonly}
    />
    <Toggle
      label={t('admin.lib.form.scanOnStart')}
      description={t('admin.lib.form.scanOnStartHelp')}
      bind:checked={form.scanOnStart}
      disabled={readonly}
    />
  </div>
</Panel>

<style>
  .form {
    display: grid;
    gap: 16px;
    max-width: 560px;
  }
</style>
