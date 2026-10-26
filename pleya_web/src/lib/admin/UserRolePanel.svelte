<!--
  Het paneel Rol van scherm 27: Beheerder, Lid en Beperkt als kaarten. De
  eigenaar is vast (hij is niet te degraderen en er is er precies één), dus
  zijn rol staat er als tekst en niet als keuze.
-->
<script lang="ts">
  import type { Role } from '../api/types';
  import Choice, { type ChoiceOption } from '../components/Choice.svelte';
  import Panel from '../components/Panel.svelte';
  import { t } from '../i18n';
  import { ASSIGNABLE_ROLES, roleHint, roleLabel } from './users';

  interface Props {
    /** De rol zoals de server hem nu kent. */
    current: Role;
    chosen: string;
  }

  let { current, chosen = $bindable() }: Props = $props();

  const options: ChoiceOption[] = ASSIGNABLE_ROLES.map((r) => ({
    value: r,
    label: roleLabel(r),
    description: roleHint(r)
  }));
</script>

<Panel>
  {#snippet title()}{t('admin.users.rolePanel.title')}{/snippet}
  {#if current === 'owner'}
    <p class="fixed"><b>{roleLabel('owner')}</b> {roleHint('owner')}.</p>
    <p class="note">{t('admin.users.rolePanel.ownerFixed')}</p>
  {:else}
    <Choice legend={t('admin.users.rolePanel.title')} hideLegend {options} bind:value={chosen} />
  {/if}
</Panel>

<style>
  .fixed {
    margin: 0 0 8px;
    font-size: 14px;
    line-height: 1.45;
    color: var(--ink-2);
  }

  .fixed b {
    color: var(--ink);
  }

  .note {
    margin: 0;
    font-size: 13px;
    line-height: 1.45;
    color: var(--ink-3);
  }
</style>
