<script lang="ts">
  import { adminSettingsApi } from '../../api/adminSettings';
  import { ApiError, describeError } from '../../api/errors';
  import type { Item, MetadataFields, MetadataOverrideField } from '../../api/types';
  import Alert from '../../components/Alert.svelte';
  import Panel from '../../components/Panel.svelte';
  import Field from '../../components/Field.svelte';
  import Select from '../../components/Select.svelte';
  import StateView from '../../components/StateView.svelte';
  import SkeletonPage from '../../components/SkeletonPage.svelte';
  import { session } from '../../stores/session.svelte';
  import { t } from '../../i18n';
  import AdminPageHead from '../AdminPageHead.svelte';
  import MetadataFieldFrame from './MetadataFieldFrame.svelte';
  import ArtworkEditor from './ArtworkEditor.svelte';
  import { metadataDraft, metadataPatch, type DirtyFields, type MetadataDraft } from './editor';

  let { itemId }: { itemId: string } = $props();
  let data = $state<MetadataFields | null>(null);
  let item = $state<Item | null>(null);
  let draft = $state<MetadataDraft | null>(null);
  let dirty = $state<DirtyFields>({});
  let invalid = $state<MetadataOverrideField[]>([]);
  let failure = $state<string | null>(null);
  let notice = $state<string | null>(null);
  let busy = $state(false);
  let attempt = $state(0);
  let sequence = 0;
  let writeController: AbortController | null = null;
  const fieldsEnabled = $derived(session.capabilities?.metadata_overrides === true);
  const enabled = $derived(session.canAdminister === true && (fieldsEnabled || session.capabilities?.artwork_choices === true));
  const changed = $derived(Object.values(dirty).some(Boolean));
  const label = (field: MetadataOverrideField) => t(`admin.metadata.editor.field.${field}`);
  const fieldError = (field: MetadataOverrideField) => invalid.includes(field) ? t('admin.metadata.editor.invalid') : undefined;
  function edit(field: MetadataOverrideField): void { dirty = { ...dirty, [field]: true }; invalid = []; failure = null; notice = null; }
  function adopt(value: MetadataFields): void { data = value; draft = metadataDraft(value); dirty = {}; invalid = []; }

  $effect(() => {
    void attempt;
    const id = itemId; const client = session.client; const generation = client.sessionGeneration; const subject = session.me?.id;
    const allowed = enabled;
    const current = ++sequence;
    const controller = new AbortController();
    writeController?.abort();
    data = null; item = null; draft = null; dirty = {}; invalid = []; failure = null; notice = null; busy = false;
    if (allowed && id) {
      Promise.all([client.item(id, controller.signal), fieldsEnabled ? adminSettingsApi(client).metadataFields(id, controller.signal) : Promise.resolve(null)])
        .then(([target, fields]) => {
          if (controller.signal.aborted || !same(id, client, generation, subject, current)) return;
          if (target.id !== id || (fields && fields.item_id !== id) || !['movie', 'show'].includes(target.kind)) throw new Error('metadata item unavailable');
          item = target; if(fields) adopt(fields);
        }).catch((error: unknown) => {
          if (!controller.signal.aborted && same(id, client, generation, subject, current)) failure = describeError(error);
        });
    }
    return () => { controller.abort(); writeController?.abort(); };
  });
  function same(id: string, client: typeof session.client, generation: number, subject: string | undefined, current: number): boolean {
    return current === sequence && itemId === id && client === session.client && generation === client.sessionGeneration && subject === session.me?.id && session.canAdminister === true && enabled;
  }
  async function write(field?: MetadataOverrideField): Promise<void> {
    if (!enabled || !fieldsEnabled || !data || !draft || busy || (field && changed)) return;
    const payload = metadataPatch(draft, dirty);
    if (!field) {
      if (!changed) return;
      invalid = payload.invalid;
      if (invalid.length || payload.tooLarge) { failure = t(payload.tooLarge ? 'admin.metadata.editor.tooLarge' : 'admin.metadata.editor.limits'); return; }
    }
    const id = itemId; const client = session.client; const generation = client.sessionGeneration; const subject = session.me?.id; const current = sequence;
    const controller = new AbortController(); writeController = controller;
    busy = true; failure = null; notice = null;
    try {
      const api = adminSettingsApi(client);
      const result = field ? await api.deleteMetadataOverride(id, field, controller.signal) : await api.setMetadataOverrides(id, payload.body, controller.signal);
      if (controller.signal.aborted || !fieldsEnabled || !same(id, client, generation, subject, current)) return;
      if (result.item_id !== id) throw new Error('metadata item mismatch');
      adopt(result);
      notice = field ? t('admin.metadata.editor.unlockedNotice', { field: label(field) }) : t('admin.metadata.editor.saved');
    } catch (error: unknown) {
      if (!controller.signal.aborted && same(id, client, generation, subject, current)) failure = error instanceof ApiError && error.code === 'library.override_source_unavailable' ? t('admin.metadata.editor.fallback') : describeError(error);
    } finally { if (same(id, client, generation, subject, current)) busy = false; }
  }
  function clear(field: 'year' | 'summary' | 'genres' | 'content_rating' | 'people'): void {
    if (!draft) return;
    if (field === 'people') draft.people = []; else draft[field] = '';
    edit(field);
  }
</script>

<div class="metadata-editor">
  <AdminPageHead title={t('admin.metadata.editor.title')} crumbs={[{ label: t('admin.match.title'), href: '/admin/metadata/match' }, { label: data?.fields.title.value ?? item?.title ?? t('admin.metadata.editor.title') }]} />
  {#if !enabled}<StateView message={t('admin.metadata.editor.unavailable')} />
  {:else if !itemId}<StateView message={t('admin.metadata.editor.missing')} />
  {:else if item}
    <nav class="item-actions" aria-label={t('admin.metadata.editor.fields')}>
      <a class="btn btn--secondary btn--sm" href="/items/{encodeURIComponent(itemId)}">{t('admin.metadata.editor.back')}</a>
      <a class="btn btn--secondary btn--sm" href="/admin/metadata/match?item={encodeURIComponent(itemId)}">{t('admin.match.title')}</a>
      {#if session.capabilities?.artwork_choices===true}<a class="btn btn--secondary btn--sm" href="#artwork">{t('admin.metadata.artwork.title')}</a>{/if}
    </nav>
    {#if fieldsEnabled && data && draft}
    <div class="editor-panel"><Panel>
      <div class="intro"><h2>{data.fields.title.value}</h2><p>{t('admin.metadata.editor.intro')}</p><p class="help">{t('admin.metadata.editor.emptyHint')}</p></div>
      {#if failure}<Alert tone="err">{failure}</Alert>{/if}
      {#if notice}<Alert tone="info">{notice}</Alert>{/if}
      <form onsubmit={event => { event.preventDefault(); void write(); }}>
        <MetadataFieldFrame field="title" source={data.fields.title.source} locked={data.fields.title.locked} dirty={Boolean(dirty.title)} disabled={busy || changed} onunlock={() => void write('title')}>
          <Field label={label('title')} hideLabel value={draft.title} maxlength={500} disabled={busy} error={fieldError('title')} oninput={value => { draft!.title = value; edit('title'); }} />
        </MetadataFieldFrame>
        <MetadataFieldFrame field="year" source={data.fields.year.source} locked={data.fields.year.locked} dirty={Boolean(dirty.year)} disabled={busy || changed} onunlock={() => void write('year')}>
          <Field label={label('year')} hideLabel value={draft.year} maxlength={4} disabled={busy} error={fieldError('year')} oninput={value => { draft!.year = value; edit('year'); }} />
          <button type="button" class="text-action" disabled={busy} onclick={() => clear('year')}>{t('admin.metadata.editor.clear', { field: label('year') })}</button>
        </MetadataFieldFrame>
        {#each ['summary', 'genres'] as field ('text-' + field)}
          {@const name = field as 'summary' | 'genres'}
          <MetadataFieldFrame field={name} source={data.fields[name].source} locked={data.fields[name].locked} dirty={Boolean(dirty[name])} disabled={busy || changed} onunlock={() => void write(name)}>
            <Field label={label(name)} hideLabel disabled={busy} error={fieldError(name)} hint={name === 'genres' ? t('admin.metadata.editor.genresHint') : undefined}>
              {#snippet children(control)}<textarea id={control.id} rows={name === 'summary' ? 5 : 3} disabled={control.disabled} aria-invalid={control.invalid} aria-describedby={control.describedby} maxlength={name === 'summary' ? 20000 : undefined} value={draft![name]} oninput={event => { draft![name] = event.currentTarget.value; edit(name); }}></textarea>{/snippet}
            </Field>
            <button type="button" class="text-action" disabled={busy} onclick={() => clear(name)}>{t('admin.metadata.editor.clear', { field: label(name) })}</button>
          </MetadataFieldFrame>
        {/each}
        <MetadataFieldFrame field="content_rating" source={data.fields.content_rating.source} locked={data.fields.content_rating.locked} dirty={Boolean(dirty.content_rating)} disabled={busy || changed} onunlock={() => void write('content_rating')}>
          <Field label={label('content_rating')} hideLabel value={draft.content_rating} maxlength={100} disabled={busy} error={fieldError('content_rating')} oninput={value => { draft!.content_rating = value; edit('content_rating'); }} />
          <button type="button" class="text-action" disabled={busy} onclick={() => clear('content_rating')}>{t('admin.metadata.editor.clear', { field: label('content_rating') })}</button>
        </MetadataFieldFrame>
        <MetadataFieldFrame field="people" source={data.fields.people.source} locked={data.fields.people.locked} dirty={Boolean(dirty.people)} disabled={busy || changed} onunlock={() => void write('people')}>
          {#if fieldError('people')}<p class="person-error" role="alert">{fieldError('people')}</p>{/if}
          {#if !draft.people.length}<p class="help">{t('admin.metadata.editor.noPeople')}</p>{/if}
          <div class="people">
            {#each draft.people as person, index (index)}
              <div class="person">
                <Field label={t('admin.metadata.editor.name', { number: index + 1 })} value={person.name} maxlength={200} disabled={busy} oninput={value => { person.name = value; edit('people'); }} />
                <Select label={t('admin.metadata.editor.role', { number: index + 1 })} value={person.role} disabled={busy} options={[...(['actor','director','writer'].includes(person.role) ? [] : [{ value: person.role, label: t('admin.metadata.editor.unknownRole') }]), ...(['actor', 'director', 'writer'] as const).map(role => ({ value: role, label: t(`admin.metadata.editor.${role}`) }))]} onchange={value => { person.role = value; edit('people'); }} />
                <Field label={t('admin.metadata.editor.character', { number: index + 1 })} value={person.character} maxlength={200} disabled={busy} oninput={value => { person.character = value; edit('people'); }} />
                <button type="button" class="text-action remove" disabled={busy} onclick={() => { draft!.people.splice(index, 1); edit('people'); }}>{t('admin.metadata.editor.removePerson', { number: index + 1 })}</button>
              </div>
            {/each}
          </div>
          <div class="people-actions"><button type="button" class="btn btn--secondary btn--sm" disabled={busy || draft.people.length >= 100} onclick={() => { draft!.people.push({ name: '', role: 'actor', character: '' }); edit('people'); }}>{t('admin.metadata.editor.addPerson')}</button><button type="button" class="text-action" disabled={busy} onclick={() => clear('people')}>{t('admin.metadata.editor.clear', { field: label('people') })}</button></div>
        </MetadataFieldFrame>
        <div class="save-bar"><button type="submit" class="btn" disabled={busy || !changed}>{t(busy ? 'admin.metadata.editor.saving' : 'admin.metadata.editor.save')}</button><button type="button" class="btn btn--secondary" disabled={busy || !changed} onclick={() => { if (data) adopt(data); failure = null; notice = null; }}>{t('admin.metadata.editor.reset')}</button></div>
        {#if changed}<p class="help">{t('admin.metadata.editor.dirtyHint')}</p>{/if}
      </form>
      <button type="button" class="text-action reload" disabled={busy || changed} onclick={() => attempt++}>{t('admin.metadata.editor.reload')}</button>
    </Panel></div>
    {/if}
    <ArtworkEditor {itemId} defaultArtwork={item.artwork}/>
  {:else if failure}<StateView kind="error" message={failure} onRetry={() => attempt++} />
  {:else}<SkeletonPage variant="compact" />{/if}
</div>
<style>
  .metadata-editor { width: 100%; max-width: 840px; min-width: 0; }
  .editor-panel { min-width: 0; }
  .intro h2 { font-size: 22px; line-height: 1.25; overflow-wrap: anywhere; margin: 0 0 10px; }
  .intro p { color: var(--ink-2); margin: 8px 0 16px; max-width: 66ch; }
  .item-actions { display: flex; gap: 10px; flex-wrap: wrap; margin: 0 0 20px; }
  .help { color: var(--ink-2); font-size: 13px; line-height: 1.5; }
  .text-action { min-height: 44px; padding: 8px 0; color: var(--ink-2); text-align: start; font-size: 13px; background: none; border: 0; cursor: pointer; text-decoration: underline; text-underline-offset: 3px; }
  .text-action:disabled { opacity: .45; cursor: default; }
  .people { display: grid; gap: 16px; }
  .person { display: grid; grid-template-columns: minmax(0,1fr) minmax(120px,.65fr); gap: 12px; padding: 16px; background: var(--inset-bg); border-radius: 10px; }
  .person > :global(.fld):nth-child(3) { grid-column: 1 / -1; }
  .remove { grid-column: 1 / -1; }
  .people-actions, .save-bar { display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }
  .people-actions { margin-top: 14px; }
  .save-bar { padding-top: 22px; border-top: 1px solid var(--hairline-strong); }
  .reload { margin-top: 8px; }
  .person-error { color: var(--danger-ink); }
  @media (max-width: 540px) { .person { grid-template-columns: minmax(0,1fr); padding: 12px; } .save-bar { align-items: stretch; flex-direction: column; } .save-bar button { width: 100%; } }
</style>
