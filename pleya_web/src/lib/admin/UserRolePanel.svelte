<!--
  Het paneel Rol op de tab Toegang: Beheerder, Lid en Beperkt als
  segmentkeuze, met eronder wat de gekozen rol inhoudt. De eigenaar is vast
  (hij is niet te degraderen en er is er precies één), dus zijn rol staat er
  als tekst en niet als keuze.
-->
<script lang="ts">
  import type { Role } from '../api/types';
  import Panel from '../components/Panel.svelte';
  import { t } from '../i18n';
  import SegmentChoice from './SegmentChoice.svelte';
  import { ASSIGNABLE_ROLES, roleHint, roleLabel } from './users';

  interface Props {
    /** De rol zoals de server hem nu kent. */
    current: Role;
    chosen: string;
  }

  let { current, chosen = $bindable() }: Props = $props();

  const shown = $derived(current === 'owner' ? 'owner' : (chosen as Role));
</script>

<Panel>
  {#snippet title()}{t('admin.users.rolePanel.title')}{/snippet}
  {#if current !== 'owner'}
    <SegmentChoice
      label={t('admin.users.rolePanel.title')}
      options={ASSIGNABLE_ROLES.map((r) => ({ value: r, label: roleLabel(r) }))}
      value={chosen}
      onchange={(value) => (chosen = value)}
    />
  {/if}
  <p class="hint"><b>{roleLabel(shown)}</b> {roleHint(shown)}.</p>
  {#if current === 'owner'}
    <p class="note">{t('admin.users.rolePanel.ownerFixed')}</p>
  {/if}
</Panel>

<style>
  .hint {
    margin: 12px 0 0;
    font-size: 14px;
    line-height: 1.45;
    color: var(--ink-2);
  }

  .hint b {
    color: var(--ink);
  }

  .note {
    margin: 8px 0 0;
    font-size: 13px;
    line-height: 1.45;
    color: var(--ink-3);
  }
</style>
