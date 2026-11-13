<!--
  Onderhoud op scherm 22 (C-05): metadata verversen en de prullenbak legen,
  `POST /libraries/{id}/refresh-metadata` en `/empty-trash`. Alleen zichtbaar
  als de server `capabilities.library_maintenance` meldt; zonder die vlag biedt
  een client alleen de scan. Het scherm zelf staat al achter de beheergate.

  Legen is onomkeerbaar voor de catalogus en gaat daarom eerst langs een
  bevestiging. Het contract levert vooraf geen aantal; dat komt pas in het
  antwoord (`items`, de kandidaten), en de melding noemt het dan.

  Meldingen en fouten gaan naar de berichtregel van het scherm, net als bij
  Nu scannen. Een retry onthoudt de bibliotheek waar het om ging; bij legen
  opent hij de bevestiging opnieuw in plaats van meteen te sturen.
-->
<script lang="ts">
  import AdminIcon from '../components/AdminIcon.svelte';
  import ConfirmDialog from '../components/ConfirmDialog.svelte';
  import Panel from '../components/Panel.svelte';
  import { adminApi } from '../api/admin';
  import type { Library } from '../api/types';
  import { t } from '../i18n';
  import { session } from '../stores/session.svelte';
  import { maintenanceProblem, type LibraryProblem } from './libraryErrors';
  import { countLabel } from './overview';

  interface Props {
    library: Library;
    onnotice: (text: string) => void;
    onproblem: (problem: LibraryProblem, again: () => void) => void;
  }

  let { library, onnotice, onproblem }: Props = $props();

  const api = $derived(adminApi(session.client));
  const allowed = $derived(session.capabilities?.library_maintenance === true);

  let refreshing = $state(false);
  let emptying = $state(false);
  let confirmOpen = $state(false);

  async function refresh(target: Library): Promise<void> {
    if (refreshing) return;
    refreshing = true;
    try {
      const { items } = await api.refreshLibraryMetadata(target.id);
      onnotice(
        items > 0
          ? t('admin.lib.maint.refreshed', {
              name: target.title,
              titles: countLabel('admin.lib.titles', items)
            })
          : t('admin.lib.maint.refreshedNone', { name: target.title })
      );
    } catch (err) {
      onproblem(maintenanceProblem(err, target.title), () => void refresh(target));
    } finally {
      refreshing = false;
    }
  }

  async function empty(target: Library): Promise<void> {
    if (emptying) return;
    emptying = true;
    try {
      const { items } = await api.emptyLibraryTrash(target.id);
      onnotice(
        items > 0
          ? t('admin.lib.maint.emptied', {
              name: target.title,
              titles: countLabel('admin.lib.titles', items)
            })
          : t('admin.lib.maint.emptiedNone', { name: target.title })
      );
    } catch (err) {
      onproblem(maintenanceProblem(err, target.title), () => (confirmOpen = true));
    } finally {
      emptying = false;
      confirmOpen = false;
    }
  }
</script>

{#if allowed}
  <Panel>
    {#snippet title()}{t('admin.lib.maint.title')}{/snippet}
    <p class="help">{t('admin.lib.maint.refreshHelp')}</p>
    <button
      type="button"
      class="btn btn--ghost btn--sm"
      disabled={refreshing}
      aria-busy={refreshing ? 'true' : undefined}
      onclick={() => void refresh(library)}
    >
      <AdminIcon name="refresh" size={16} />{t('admin.lib.maint.refresh')}
    </button>
    <p class="help help--next">{t('admin.lib.maint.trashHelp')}</p>
    <button
      type="button"
      class="btn btn--ghost btn--sm"
      disabled={emptying}
      onclick={() => (confirmOpen = true)}
    >
      <AdminIcon name="trash" size={16} />{t('admin.lib.maint.trash')}
    </button>
  </Panel>

  <ConfirmDialog
    bind:open={confirmOpen}
    busy={emptying}
    title={t('admin.lib.maint.confirmTitle', { name: library.title })}
    message={t('admin.lib.maint.confirmBody', { name: library.title })}
    confirmLabel={t('admin.lib.maint.confirm')}
    onconfirm={() => void empty(library)}
  >
    {#snippet confirmIcon()}<AdminIcon name="trash" size={18} />{/snippet}
  </ConfirmDialog>
{/if}

<style>
  .help {
    margin: 0 0 12px;
    font-size: 13px;
    line-height: 1.45;
    color: var(--ink-3);
  }

  .help--next {
    margin-top: 16px;
  }
</style>
