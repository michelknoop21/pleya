<!--
  Nieuw token (34, rechts): naam, bereik en geldigheid. Het token gaat altijd
  over de ingelogde beheerder zelf (zonder `user_id`); de northstar tekent geen
  eigenaarsveld. Standaardbereik is alleen lezen, het kleinste: de northstar
  zet Beheer voorop, maar een agent die per ongeluk met te veel macht begint is
  erger dan een klik meer. Een bereik dat de adminklasse haalt vraagt de pagina
  om een bevestiging, dat gebeurt buiten dit paneel.

  Zolang het geheim van het vorige token open staat is aanmaken uit: een tweede
  token zou het eerste geheim vervangen en dat is niet terug te halen.
-->
<script lang="ts">
  import Choice, { type ChoiceOption } from '../../components/Choice.svelte';
  import Field from '../../components/Field.svelte';
  import Panel from '../../components/Panel.svelte';
  import Select from '../../components/Select.svelte';
  import { t } from '../../i18n';
  import {
    DEFAULT_EXPIRY_DAYS,
    EXPIRY_DAYS,
    NAME_MAX,
    SCOPES,
    nameProblem,
    scopeHint,
    scopeLabel
  } from './tokens';

  interface Props {
    busy: boolean;
    /** Een geheim staat nog open: aanmaken is dan uit. */
    locked: boolean;
    /** Geeft true terug als het token er is; dan gaat de naam leeg. */
    onsubmit: (request: { name: string; scope: string; days: number }) => Promise<boolean>;
  }

  let { busy, locked, onsubmit }: Props = $props();

  let name = $state('');
  let scope = $state<string>('read');
  let days = $state(String(DEFAULT_EXPIRY_DAYS));
  let submitted = $state(false);

  const problem = $derived(nameProblem(name));

  // Hoogste bereik bovenaan, zoals de northstar.
  const scopeOptions: ChoiceOption[] = [...SCOPES].reverse().map((s) => ({
    value: s,
    label: scopeLabel(s).replace(/^./, (c) => c.toUpperCase()),
    description: scopeHint(s)
  }));
  const dayOptions = EXPIRY_DAYS.map((d) => ({
    value: String(d),
    label: t('admin.tok.form.expiresOption', { count: d })
  }));

  async function submit(): Promise<void> {
    submitted = true;
    if (busy || locked || problem) return;
    if (await onsubmit({ name: name.trim(), scope, days: Number(days) })) {
      name = '';
      submitted = false;
    }
  }
</script>

<Panel>
  {#snippet title()}{t('admin.tok.form.title')}{/snippet}
  <form
    class="form"
    novalidate
    onsubmit={(e) => {
      e.preventDefault();
      void submit();
    }}
  >
    <Field
      label={t('admin.tok.form.name')}
      bind:value={name}
      autocomplete="off"
      required
      disabled={locked}
      hint={t('admin.tok.form.nameHint')}
      error={submitted && problem ? t(problem) : undefined}
      maxlength={NAME_MAX}
    />
    <Choice
      legend={t('admin.tok.form.scope')}
      options={scopeOptions}
      bind:value={scope}
      disabled={locked}
    />
    <Select
      label={t('admin.tok.form.expires')}
      options={dayOptions}
      bind:value={days}
      disabled={locked}
      hint={t('admin.tok.form.expiresHint')}
    />
    {#if locked}<p class="locked">{t('admin.tok.form.locked')}</p>{/if}
    <div>
      <button
        type="submit"
        class="btn"
        disabled={busy || locked}
        aria-busy={busy ? 'true' : undefined}
      >
        {t('admin.tok.form.submit')}
      </button>
    </div>
  </form>
</Panel>

<style>
  .form {
    display: grid;
    gap: 18px;
  }

  .locked {
    margin: 0;
    font-size: 12.5px;
    color: var(--ink-3);
  }
</style>
