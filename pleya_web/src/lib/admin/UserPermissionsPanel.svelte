<!--
  Het paneel Bibliotheken op de tab Toegang: per bibliotheek één segmentkeuze
  met de niveaus van de ladder uit DEC-119 (kijken, downloaden, beheren) en
  geen recht. Een bibliotheek op Geen bestaat voor de gebruiker niet. Een
  beperkte gebruiker krijgt Beheren niet aangeboden.

  Het contract heeft geen leesroute voor de rechten die een gebruiker nu heeft.
  Het paneel begint daarom zonder keuze en zegt dat: geen enkel segment is
  gekozen, ook Geen niet. Pas na een eerste keuze telt het als aangeraakt; dan
  staan de overige bibliotheken op Geen, want Opslaan schrijft (na een
  bevestiging) de hele lijst. Een eigenaar of beheerder heeft geen
  rechtenrijen: zijn toegang volgt uit de rol, dus het paneel toont dan alleen
  die uitleg.
-->
<script lang="ts">
  import type { Library, Role } from '../api/types';
  import Alert from '../components/Alert.svelte';
  import Panel from '../components/Panel.svelte';
  import { t } from '../i18n';
  import { countLabel } from './overview';
  import SegmentChoice from './SegmentChoice.svelte';
  import { levelsFor, rungLabel, seesEverything, setGrant, type Grants, type Level } from './users';

  interface Props {
    name: string;
    role: Role;
    libraries: Library[];
    grants: Grants;
    /** Of de beheerder een niveau gekozen heeft; alleen dan wordt er geschreven. */
    touched: boolean;
    /** Of het paneel de lijst toont die de server na een schrijfactie teruggaf. */
    confirmedByServer: boolean;
  }

  let {
    name,
    role,
    libraries,
    grants = $bindable(),
    touched = $bindable(),
    confirmedByServer
  }: Props = $props();

  const options = $derived(levelsFor(role).map((l) => ({ value: l, label: rungLabel(l) })));
  const known = $derived(touched || confirmedByServer);

  function change(libraryId: string, level: string): void {
    grants = setGrant(grants, libraryId, level as Level);
    touched = true;
  }
</script>

<Panel>
  {#snippet title()}{t('admin.users.perm.title')}{/snippet}
  {#if seesEverything(role)}
    <p class="note">{t('admin.users.perm.byRole', { name })}</p>
  {:else}
    {#if !touched}
      <div class="info">
        <Alert tone="info" live={false}>
          {t(known ? 'admin.users.perm.confirmed' : 'admin.users.perm.unreadable', { name })}
        </Alert>
      </div>
    {/if}
    {#if libraries.length === 0}
      <p class="note">{t('admin.users.perm.noLibraries')}</p>
    {:else}
      <ul class="list">
        {#each libraries as library (library.id)}
          <li class="row" data-library={library.id}>
            <span class="lib">
              <span class="name">{library.title}</span>
              <span class="meta">{countLabel('admin.lib.titles', library.item_count)}</span>
            </span>
            <SegmentChoice
              label={t('admin.users.perm.groupNamed', { library: library.title })}
              {options}
              value={grants[library.id] ?? (known ? 'none' : '')}
              onchange={(level) => change(library.id, level)}
            />
          </li>
        {/each}
      </ul>
    {/if}
    <p class="note foot">
      {t('admin.users.perm.footnote', { name })}
      {#if role === 'restricted'}{t('admin.users.perm.noManage')}{/if}
    </p>
  {/if}
</Panel>

<style>
  .info {
    margin-bottom: 6px;
  }

  .list {
    display: grid;
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 10px 16px;
    padding: 12px 0;
    border-bottom: 1px solid var(--hairline);
  }

  .lib {
    display: grid;
    flex: 1 1 160px;
    min-width: 0;
  }

  .name {
    font-size: 15px;
    font-weight: 500;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .meta {
    font-size: 13px;
    color: var(--ink-3);
  }

  .note {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }

  .foot {
    margin-top: 12px;
  }
</style>
