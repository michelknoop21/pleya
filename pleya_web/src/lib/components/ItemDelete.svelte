<!--
  Een titel met zijn bestanden verwijderen (17h, `DELETE /items/{id}`). Alleen
  de bevestiging en de afhandeling; wie de knop toont (ItemAdminMenu,
  SeriesDetail) zet `open`. Er is geen prullenbak op schijf, dus de dialoog
  zegt wat er weggaat.

  De uitkomst komt in de paginamelding van de schil (pageNotice): na succes
  bestaat deze pagina niet meer, en bij een onvolledige verwijdering leest de
  pagina het item opnieuw en zou een melding hier mee verdwijnen.
-->
<script lang="ts">
  import { goto } from '$app/navigation';
  import { adminSettingsApi } from '../api/adminSettings';
  import { ApiError, describeError } from '../api/errors';
  import type { Item } from '../api/types';
  import { plural, t, type MessageKey } from '../i18n';
  import { pageNotice, type PageNotice } from '../stores/pageNotice.svelte';
  import { session } from '../stores/session.svelte';
  import ConfirmDialog from './ConfirmDialog.svelte';

  let {
    item,
    open = $bindable(false),
    onreload
  }: { item: Pick<Item, 'id' | 'title' | 'kind' | 'parent_id'>; open?: boolean; onreload?: () => void } = $props();

  let busy = $state(false);
  const withChildren = $derived(item.kind === 'show' || item.kind === 'season');

  const UNAVAILABLE: Record<string, MessageKey> = {
    disabled: 'item.delete.err.disabled',
    read_only: 'item.delete.err.readOnly',
    root_overlap: 'item.delete.err.rootOverlap'
  };
  const CODES: Record<string, MessageKey> = {
    'library.scan_in_progress': 'item.delete.err.scan',
    'storage.unavailable': 'item.delete.err.storage',
    'library.delete_not_permitted': 'item.delete.err.notPermitted'
  };

  // Een film of serie heeft geen bovenliggende pagina, dan het overzicht.
  const overview = (): string => (item.kind === 'movie' ? '/films' : '/series');

  // De ouders van een seizoen of aflevering, dichtstbijzijnde eerst. De server
  // ruimt een seizoen of serie op dat door het verwijderen leeg raakt, dus wie
  // de laatste aflevering wist, heeft daarna geen seizoen meer. De serie boven
  // een aflevering moet daarom vóór het verwijderen bekend zijn.
  async function ancestors(client: typeof session.client): Promise<string[]> {
    if ((item.kind !== 'season' && item.kind !== 'episode') || !item.parent_id) return [];
    if (item.kind === 'season') return [item.parent_id];
    try {
      const parent = await client.item(item.parent_id);
      return parent.parent_id ? [item.parent_id, parent.parent_id] : [item.parent_id];
    } catch {
      return [item.parent_id];
    }
  }

  // De eerste ouder die nog bestaat, anders het overzicht.
  async function destination(client: typeof session.client, chain: string[]): Promise<string> {
    for (const id of chain) {
      try {
        await client.item(id);
        return `/items/${encodeURIComponent(id)}`;
      } catch (err) {
        if (!(err instanceof ApiError && err.status === 404)) return `/items/${encodeURIComponent(id)}`;
      }
    }
    return overview();
  }

  function count(value: unknown): number {
    return typeof value === 'number' && Number.isFinite(value) ? value : 0;
  }

  function problem(err: unknown): string {
    if (!(err instanceof ApiError)) return describeError(err);
    const title = item.title;
    if (err.status === 404) return t('item.delete.err.notFound', { title });
    if (err.code === 'library.media_delete_unavailable') {
      const reason = err.details['reason'];
      return t((typeof reason === 'string' && UNAVAILABLE[reason]) || 'item.delete.err.unavailable', { title });
    }
    const key = CODES[err.code];
    return key ? t(key, { title }) : describeError(err);
  }

  function failedLines(err: ApiError): string[] {
    const failed = err.details['failed'];
    if (!Array.isArray(failed)) return [];
    return failed.map((entry: { path?: unknown; reason?: unknown }) => {
      const path = typeof entry?.path === 'string' ? entry.path : '';
      const reason = typeof entry?.reason === 'string' ? entry.reason : '';
      const key = `item.delete.reason.${reason}` as MessageKey;
      const text = t(key);
      return `${path}: ${text === key ? reason : text}`;
    });
  }

  async function show(path: string, notice: Omit<PageNotice, 'path'>): Promise<void> {
    await goto(path);
    pageNotice.current = { path, ...notice };
  }

  async function remove(): Promise<void> {
    // `busy` zet de bevestigknop van ConfirmDialog meteen uit, ook voor een
    // tweede klik in hetzelfde frame: één aanvraag.
    busy = true;
    const client = session.client;
    const chain = await ancestors(client);
    try {
      const result = await adminSettingsApi(client).deleteItem(item.id);
      busy = false;
      open = false;
      await show(await destination(client, chain), { tone: 'info', text: plural('item.delete.done', result.removed_files, { title: item.title }), lines: [] });
    } catch (err) {
      busy = false;
      open = false;
      const here = location.pathname;
      if (!(err instanceof ApiError) || err.code !== 'library.media_delete_incomplete') {
        pageNotice.current = { path: here, tone: 'err', text: problem(err), lines: [] };
        return;
      }
      const notice = {
        tone: 'err' as const,
        text: t('item.delete.incomplete', { title: item.title, files: count(err.details['removed_files']), items: count(err.details['removed_items']) }),
        lines: failedLines(err)
      };
      pageNotice.current = { path: here, ...notice };
      if (count(err.details['removed_items']) === 0 && count(err.details['removed_files']) === 0) return;
      // Er ging wel iets weg (ook een losse versie telt): lees het item
      // opnieuw. Is het zelf weg, dan naar de eerste ouder die nog bestaat.
      try {
        await client.item(item.id);
        onreload?.();
      } catch (readErr) {
        if (readErr instanceof ApiError && readErr.status === 404) await show(await destination(client, chain), notice);
      }
    }
  }
</script>

<ConfirmDialog
  bind:open
  title={t('item.delete.title', { title: item.title })}
  message={withChildren ? `${t('item.delete.message')} ${t('item.delete.children')}` : t('item.delete.message')}
  confirmLabel={t('item.delete.confirm')}
  danger
  {busy}
  onconfirm={() => void remove()}
/>
