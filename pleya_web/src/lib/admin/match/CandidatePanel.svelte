<!--
  De kandidaten van één titel (36, midden): kies er één, vul zelf een nummer
  in, of wijs de match af. Een alternatief van de server heeft alleen een
  nummer, een titel en een jaar, dus er staan geen posters of scores op; de
  northstar tekent ze, het contract levert ze niet.

  Dit paneel stuurt niets. Kiezen, een nummer gebruiken en afwijzen melden zich
  bij de pagina, die er eerst een bevestiging voor zet.
-->
<script lang="ts">
  import type { MetadataAttention } from '../../api/types';
  import Alert from '../../components/Alert.svelte';
  import Choice, { type ChoiceOption } from '../../components/Choice.svelte';
  import Field from '../../components/Field.svelte';
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';
  import { canReject, isValidExternalId, titleOf } from './match';

  interface Props {
    item: MetadataAttention;
    busy: boolean;
    onpick: (externalId: string, label: string) => void;
    onreject: () => void;
  }

  let { item, busy, onpick, onreject }: Props = $props();

  let choice = $state('');
  let manual = $state('');
  let manualError = $state<string | undefined>(undefined);

  // Een andere titel begint met een leeg formulier.
  $effect(() => {
    void item.item_id;
    choice = '';
    manual = '';
    manualError = undefined;
  });

  const options = $derived<ChoiceOption[]>(
    item.alternatives.map((a) => ({
      value: a.external_id,
      label: a.year ? `${a.title} (${a.year})` : a.title,
      description: a.year
        ? t('admin.match.cand.detail', { year: a.year, id: a.external_id })
        : t('admin.match.cand.detailNoYear', { id: a.external_id })
    }))
  );

  function pick(): void {
    const chosen = options.find((o) => o.value === choice);
    if (chosen) onpick(chosen.value, chosen.label);
  }

  function useManual(): void {
    const value = manual.trim();
    if (!isValidExternalId(value)) {
      manualError = t('admin.match.manual.invalid');
      return;
    }
    manualError = undefined;
    onpick(value, t('admin.match.cand.number', { id: value }));
  }
</script>

<Panel>
  {#snippet title()}{titleOf(item)}{/snippet}
  {#snippet actions()}<span class="hint">{t('admin.match.cand.hint')}</span>{/snippet}

  <div class="body">
    {#if item.state === 'rejected'}
      <Alert tone="info">{t('admin.match.cand.rejected')}</Alert>
    {/if}

    {#if options.length > 0}
      <Choice
        legend={t('admin.match.cand.legend')}
        hideLegend
        {options}
        bind:value={choice}
        disabled={busy}
      />
    {:else if item.state !== 'rejected'}
      <p class="none">{t('admin.match.cand.none')}</p>
    {/if}

    <div class="actions">
      {#if options.length > 0}
        <button
          type="button"
          class="btn btn--primary"
          disabled={busy || choice === ''}
          onclick={pick}
        >
          {t('admin.match.cand.pick')}
        </button>
      {/if}
      {#if canReject(item)}
        <button type="button" class="btn btn--secondary" disabled={busy} onclick={onreject}>
          {t('admin.match.cand.reject')}
        </button>
      {/if}
    </div>

    <form
      class="manual"
      onsubmit={(event) => {
        event.preventDefault();
        useManual();
      }}
    >
      <Field
        label={t('admin.match.manual.label')}
        hint={t('admin.match.manual.hint')}
        error={manualError}
        bind:value={manual}
        mono
        maxlength={10}
        disabled={busy}
        autocomplete="off"
      />
      <button type="submit" class="btn btn--secondary" disabled={busy || manual.trim() === ''}>
        {t('admin.match.manual.use')}
      </button>
    </form>

    <p class="foot">{t('admin.match.cand.foot')}</p>
  </div>
</Panel>

<style>
  .body {
    display: grid;
    gap: 16px;
  }

  .hint,
  .foot,
  .none {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
  }

  .manual {
    display: grid;
    gap: 10px;
    justify-items: start;
    padding-top: 16px;
    border-top: 1px solid var(--hairline);
  }

  @media (max-width: 899px) {
    .actions .btn,
    .manual .btn {
      justify-content: center;
      width: 100%;
      min-height: 44px;
    }

    .manual {
      justify-items: stretch;
    }
  }
</style>
