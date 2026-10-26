<!--
  Het paneel Opslagroots van scherm 22. De keuze komt uit `GET /storage/roots`
  en nergens anders: een pad typen kan niet (K rij 10, het dreigingsmodel).
  Een root van een andere bibliotheek staat erbij maar is niet te kiezen, met
  wie hem heeft; de server weigert overlap, en dat hoort niemand pas na
  Opslaan te horen.

  Een gewone checkbox en geen eigen primitief: de browser levert de rol, de
  toets en de staat, en `accent-color` zet hem in de inkt van het thema.
-->
<script lang="ts">
  import Panel from '../components/Panel.svelte';
  import StatusPill from '../components/StatusPill.svelte';
  import type { StorageRoot } from '../api/types';
  import { t } from '../i18n';
  import { formatBytes } from '../util/format';
  import { rootChoices } from './libraries';

  interface Props {
    roots: StorageRoot[];
    selected: string[];
    libraryId: string | null;
    readonly?: boolean;
    error?: string;
  }

  let { roots, selected = $bindable(), libraryId, readonly = false, error }: Props = $props();

  const uid = $props.id();
  const choices = $derived(rootChoices(roots, libraryId));
  const free = $derived(choices.filter((c) => c.takenBy === null));

  function trustText(root: StorageRoot): string {
    if (!root.inode_trusted) return t('admin.lib.root.untrusted');
    if (root.inode_trust_source === 'measured') return t('admin.lib.root.trustedMeasured');
    if (root.inode_trust_source === 'config_override') return t('admin.lib.root.trustedConfig');
    return t('admin.lib.root.trustedDefault');
  }

  function detail(root: StorageRoot, takenBy: string | null): string {
    if (takenBy) return t('admin.lib.root.takenBy', { name: takenBy });
    const parts = [root.fs_type ?? '', trustText(root)];
    if (root.mounted) parts.push(t('admin.lib.root.free', { size: formatBytes(root.free_bytes) }));
    return parts.filter(Boolean).join(' · ');
  }

  function toggle(path: string, on: boolean): void {
    selected = on ? [...selected, path].sort() : selected.filter((p) => p !== path);
  }
</script>

<Panel>
  {#snippet title()}{t('admin.lib.form.roots')}{/snippet}
  <p class="help" id={`${uid}-help`}>{t('admin.lib.form.rootsHelp')}</p>
  {#if error}
    <p class="help help--err" id={`${uid}-err`}>{error}</p>
  {/if}
  {#if free.length === 0 && selected.length === 0}
    <p class="empty">
      {t('admin.lib.form.noFreeRoots')}
      <a href="/admin/storage">{t('admin.alert.action')}</a>
    </p>
  {/if}
  <ul class="list" aria-describedby={error ? `${uid}-err` : `${uid}-help`}>
    {#each choices as choice, i (choice.root.path)}
      {@const root = choice.root}
      {@const id = `${uid}-root${i}`}
      <li class="row" class:row--off={choice.takenBy !== null}>
        <input
          {id}
          type="checkbox"
          checked={selected.includes(root.path)}
          disabled={readonly || choice.takenBy !== null}
          aria-describedby={`${id}-sub`}
          onchange={(event) => toggle(root.path, event.currentTarget.checked)}
        />
        <label class="body" for={id}>
          <span class="t mono">{root.path}</span>
          <span class="s" id={`${id}-sub`}>{detail(root, choice.takenBy)}</span>
        </label>
        {#if choice.takenBy === null}
          {#if !root.mounted}
            <StatusPill size="sm" tone="err" label={t('admin.lib.root.unmounted')} />
          {:else if !root.inode_trusted}
            <StatusPill size="sm" tone="warn" label={t('admin.lib.root.untrustedShort')} />
          {:else}
            <StatusPill size="sm" tone="ok" label={t('admin.lib.root.mounted')} />
          {/if}
        {/if}
      </li>
    {/each}
  </ul>
</Panel>

<style>
  .help {
    margin: 0 0 10px;
    font-size: 13px;
    line-height: 1.45;
    color: var(--ink-3);
  }

  .help--err {
    color: var(--danger-ink);
  }

  .empty {
    margin: 0 0 10px;
    font-size: 14px;
    line-height: 1.45;
    color: var(--ink-2);
  }

  .empty a {
    color: var(--ink);
    text-decoration: underline;
  }

  .list {
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .row {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr) auto;
    align-items: center;
    gap: 12px;
    padding: 12px 0;
    border-top: 1px solid var(--hairline);
  }

  .row:first-child {
    border-top: 0;
  }

  input {
    width: 20px;
    height: 20px;
    margin: 0;
    accent-color: var(--ink);
  }

  .body {
    display: grid;
    gap: 2px;
    min-width: 0;
    cursor: pointer;
  }

  .row--off .body {
    cursor: default;
  }

  .t {
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .row--off .t {
    color: var(--ink-3);
  }

  .s {
    font-size: 13px;
    color: var(--ink-3);
  }
</style>
