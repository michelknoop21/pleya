<script lang="ts">
  import ArtworkCredits from '../metadata/ArtworkCredits.svelte';
  import { untrack } from 'svelte';
  import type { MetadataSearchCandidate, MetadataCandidateDetails } from '../../api/types';
  import { adminSettingsApi } from '../../api/adminSettings';
  import { ApiError } from '../../api/errors';
  import { session } from '../../stores/session.svelte';
  import Alert from '../../components/Alert.svelte';
  import Choice, { type ChoiceOption } from '../../components/Choice.svelte';
  import Field from '../../components/Field.svelte';
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';
  import { canReject, isValidExternalId, titleOf, type MatchTarget } from './match';

  interface Props {
    item: MatchTarget; busy: boolean; choiceReceived?: boolean;
    onpick: (externalId: string, label: string) => void; onreject: () => void;
  }
  let { item, busy, choiceReceived=false, onpick, onreject }: Props = $props();
  const enabled = $derived(session.capabilities?.metadata_search === true && session.canAdminister !== false);
  const context = $derived(`${item.item_id}:${session.client.sessionGeneration}:${session.me?.id ?? ''}:${session.canAdminister}`);
  let queryTitle = $state(''); let year = $state('');
  let choice = $state(''); let manual = $state('');
  let manualError = $state<string | undefined>();
  let candidates = $state<MetadataSearchCandidate[] | null>(null);
  let details = $state<MetadataCandidateDetails | null>(null);
  let poster = $state<string | null>(null);
  let searchBusy = $state(false); let detailBusy = $state(false);
  let searchError = $state<string | null>(null); let detailError = $state<string | null>(null); let imageError = $state(false);
  let searchController: AbortController | null = null;
  let detailController: AbortController | null = null;
  let searchSequence = 0; let detailSequence = 0;

  function clearPoster(): void { if (poster) URL.revokeObjectURL(poster); poster = null; }
  function cancel(): void { searchController?.abort(); searchSequence++; searchBusy = false; }
  function cancelDetails(): void { detailController?.abort(); detailSequence++; detailBusy = false; clearPoster(); }
  $effect(() => {
    void context; void enabled;
    untrack(() => {
      cancel(); cancelDetails(); queryTitle = item.title; year = item.year?.toString() ?? '';
      choice = ''; manual = ''; manualError = undefined; candidates = null; details = null; searchError = null; detailError = null; imageError = false;
    });
    return () => { cancel(); cancelDetails(); };
  });
  const options = $derived<ChoiceOption[]>(item.alternatives.map((a) => ({value:a.external_id,label: a.year ? `${a.title} (${a.year})` : a.title,description: a.year ? t('admin.match.cand.detail',{year:a.year,id:a.external_id}) : t('admin.match.cand.detailNoYear',{id:a.external_id})})));
  function safeError(err: unknown): string {
    return t(err instanceof ApiError && err.status === 429 ? 'admin.match.search.rate' : err instanceof ApiError && err.status === 503 ? 'admin.match.search.off' : 'admin.match.search.failed');
  }
  async function search(): Promise<void> {
    if (!enabled || busy) return;
    const query=queryTitle.trim(); const rawYear=year.trim();
    if (!query || [...query].length>200 || /[\u0000-\u001f\u007f]/.test(query) || (rawYear!=='' && !/^[1-9][0-9]{0,3}$/.test(rawYear))) {searchError=t('admin.match.search.invalid');return;}
    cancel(); cancelDetails(); choice=''; details=null; candidates=null; searchError=null; detailError=null; imageError=false;
    const controller=new AbortController(); searchController=controller; const seq=++searchSequence; const ctx=context; const id=item.item_id; const client=session.client; const generation=client.sessionGeneration; const subject=session.me?.id;
    searchBusy=true;
    try {
      const result=await adminSettingsApi(session.client).searchMetadata(id,query,rawYear ? Number(rawYear) : undefined,controller.signal);
      if (controller.signal.aborted || ctx!==context || seq!==searchSequence || !enabled || session.client!==client || client.sessionGeneration!==generation || session.me?.id!==subject) return;
      candidates=result.items;
    } catch(err) {if (!controller.signal.aborted && ctx===context && seq===searchSequence && enabled && session.client===client && client.sessionGeneration===generation && session.me?.id===subject) searchError=safeError(err);}
    finally {if(ctx===context && seq===searchSequence) searchBusy=false;}
  }
  async function select(candidate: MetadataSearchCandidate): Promise<void> {
    if (!enabled || busy) return;
    cancelDetails(); choice=candidate.external_id; details=null; detailError=null; imageError=false;
    const controller=new AbortController(); detailController=controller; const seq=++detailSequence; const ctx=context; const id=item.item_id; const client=session.client; const generation=client.sessionGeneration; const subject=session.me?.id;
    const live=() => !controller.signal.aborted && ctx===context && seq===detailSequence && enabled && session.client===client && client.sessionGeneration===generation && session.me?.id===subject;
    detailBusy=true;
    try {
      const result=await adminSettingsApi(session.client).metadataCandidate(id,candidate.external_id,controller.signal);
      if (!live()) return;
      if(result.external_id!==candidate.external_id) throw new Error('candidate mismatch');
      details=result;
      if(result.poster_ref) {
        try {
          const blob=await adminSettingsApi(session.client).metadataCandidateArtwork(id,result.poster_ref,'poster',controller.signal);
          if(live()) poster=URL.createObjectURL(blob);
        } catch {if(live()) imageError=true;}
      }
    } catch(err) {if(live()) detailError=safeError(err);}
    finally {if(live()) detailBusy=false;}
  }
  function pick(): void {
    if (enabled) {const c=candidates?.find(c=>c.external_id===choice);if(c && details?.external_id===choice) onpick(choice,c.year ? `${c.title} (${c.year})` : c.title);}
    else {const c=options.find(o=>o.value===choice);if(c) onpick(c.value,c.label);}
  }
  function useManual(): void {
    const value=manual.trim();if(!isValidExternalId(value)){manualError=t('admin.match.manual.invalid');return;}
    manualError=undefined;onpick(value,t('admin.match.cand.number',{id:value}));
  }
</script>

<Panel>
  {#snippet title()}{titleOf(item)}{/snippet}
  <div class="body">
    {#if item.state==='rejected' && !choiceReceived}<Alert tone="info">{t('admin.match.cand.rejected')}</Alert>{/if}
    {#if enabled}
      <form class="search" onsubmit={(e)=>{e.preventDefault();void search();}}>
        <div class="query"><Field label={t('admin.match.search.title')} bind:value={queryTitle} maxlength={200} disabled={busy} /></div>
        <div class="year"><Field label={t('admin.match.search.year')} bind:value={year} maxlength={4} disabled={busy} /></div>
        <button class="btn btn--primary" type="submit" disabled={busy || searchBusy}>{t(searchBusy ? 'admin.match.search.loading':'admin.match.search.submit')}</button>
      </form>
      {#if searchBusy}<button class="btn btn--secondary" onclick={cancel}>{t('admin.match.search.cancel')}</button>{/if}
      {#if searchError}<Alert tone="err">{searchError}</Alert><button class="btn btn--secondary" onclick={()=>void search()}>{t('admin.match.search.retry')}</button>{/if}
      {#if candidates}
        <div class="result-head"><strong>{t('admin.match.cand.legend')}</strong><span>{t('admin.match.search.results',{count:candidates.length})}</span></div>
        {#if candidates.length===0}<p class="hint">{t('admin.match.search.empty')}</p>{/if}
        <div class="cards" role="radiogroup" aria-label={t('admin.match.cand.legend')}>
          {#each candidates as candidate (candidate.external_id)}
            <label class:selected={choice===candidate.external_id} class="card">
              <input type="radio" name="candidate" value={candidate.external_id} checked={choice===candidate.external_id} disabled={busy} onchange={()=>void select(candidate)} />
              <span class="poster">{#if choice===candidate.external_id && poster}<img src={poster} alt="" />{:else}<span aria-hidden="true">P</span>{/if}</span>
              <span class="identity"><strong>{candidate.title}</strong><span class="candidate-year">{candidate.year ?? t('admin.match.search.unknownYear')}</span><small>TMDB {candidate.external_id}</small>{#if candidate.original_title && candidate.original_title!==candidate.title}<small>{t('admin.match.search.original',{title:candidate.original_title})}</small>{/if}</span>
            </label>
          {/each}
        </div>
      {/if}
      {#if detailBusy}<p class="hint" role="status">{t('admin.match.status.loading')}</p>{/if}
      {#if detailError}<Alert tone="err">{detailError}</Alert><button class="btn btn--secondary" onclick={()=>{const c=candidates?.find(c=>c.external_id===choice);if(c) void select(c);}}>{t('admin.match.search.retry')}</button>{/if}
      {#if details}
        <section class="comparison" aria-label={t('admin.match.search.details')}>
          <p>{t('admin.match.search.current',{title:titleOf(item)})}</p>
          {#if details.summary}<p>{details.summary}</p>{/if}
          {#if details.genres.length}<p>{details.genres.join(' · ')}</p>{/if}
          {#if details.content_rating}<p>{details.content_rating}</p>{/if}
          <p class="hint">{t('admin.match.search.preview')}</p>
        </section>
      {/if}
      {#if imageError}<p class="hint">{t('admin.match.search.imageError')}</p>{/if}
      {#if details}<ArtworkCredits/>{/if}
      <div class="apply"><p class="hint">{t('admin.match.search.choose')}</p><button type="button" class="btn btn--primary" disabled={busy || !choice || details?.external_id!==choice || detailBusy} onclick={pick}>{t('admin.match.search.pick')}</button></div>
    {:else}
      {#if options.length>0}<Choice legend={t('admin.match.cand.legend')} hideLegend {options} bind:value={choice} disabled={busy}/><button type="button" class="btn btn--primary" disabled={busy || !choice} onclick={pick}>{t('admin.match.cand.pick')}</button>
      {:else if item.state!=='rejected'}<p class="hint">{t('admin.match.cand.none')}</p>{/if}
    {/if}
    <details class="advanced" open={!enabled}>
      <summary>{t('admin.match.search.advanced')}</summary>
      <div class="advanced-body">
        {#if canReject(item) || choiceReceived}<button type="button" class="btn btn--secondary" disabled={busy} onclick={onreject}>{t('admin.match.cand.reject')}</button>{/if}
        <form class="manual" onsubmit={(e)=>{e.preventDefault();useManual();}}>
          <Field label={t('admin.match.manual.label')} hint={t('admin.match.manual.hint')} error={manualError} bind:value={manual} mono maxlength={10} disabled={busy} autocomplete="off"/>
          <button type="submit" class="btn btn--secondary" disabled={busy || !manual.trim()}>{t('admin.match.manual.use')}</button>
        </form>
        <p class="hint">{t('admin.match.cand.foot')}</p>
      </div>
    </details>
  </div>
</Panel>
<style>
 .body{display:grid;gap:18px;min-width:0}.hint{margin:0;color:var(--ink-3);font-size:13px;line-height:1.5}.search{display:grid;grid-template-columns:minmax(0,1fr) 118px auto;gap:12px;align-items:end}.result-head,.apply{display:flex;justify-content:space-between;align-items:center;gap:16px}.result-head span{font-size:12px;color:var(--ink-3)}.cards{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.card{position:relative;display:flex;gap:14px;padding:12px;padding-right:34px;border:1px solid var(--hairline);border-radius:13px;cursor:pointer;min-width:0;background:var(--panel-2)}.card.selected{border-color:var(--accent)}.card:focus-within{outline:2px solid var(--accent);outline-offset:3px}.card input{position:absolute;right:12px;top:14px;accent-color:var(--accent)}.poster{width:88px;min-width:88px;height:132px;border-radius:7px;overflow:hidden;display:grid;place-items:center;background:var(--inset-bg);color:var(--ink-3)}.poster img{width:100%;height:100%;object-fit:cover}.poster>span{font-size:38px;font-weight:800;opacity:.35}.identity{display:flex;flex-direction:column;justify-content:center;gap:5px;min-width:0;overflow-wrap:anywhere}.identity strong{font-size:15px}.candidate-year{font-size:18px}.identity small{font-size:11px;color:var(--ink-3)}.comparison{padding:14px;border:1px solid var(--hairline);border-radius:10px;font-size:14px;line-height:1.5;overflow-wrap:anywhere}.comparison p{margin:0 0 9px}.comparison p:last-child{margin:0}.advanced{border-top:1px solid var(--hairline);padding-top:18px}.advanced summary{cursor:pointer;color:var(--ink-3);font-size:13px;min-height:24px}.advanced-body{display:grid;gap:16px;padding-top:12px}.manual{display:grid;gap:10px;justify-items:start}
 @media(max-width:899px){.search{grid-template-columns:minmax(0,1fr) auto}.query{grid-column:1;grid-row:1}.search>.btn{grid-column:2;grid-row:1;min-height:44px}.year{grid-column:1;grid-row:2;max-width:150px}.cards{grid-template-columns:minmax(0,1fr)}.apply{align-items:stretch;flex-direction:column;gap:10px}.apply .btn,.manual .btn,.advanced-body>.btn{width:100%;min-height:44px;justify-content:center}.manual{justify-items:stretch}.poster{width:70px;min-width:70px;height:105px}.card{gap:12px}.result-head{align-items:start}.result-head span{white-space:nowrap}}
 @media(prefers-reduced-motion:reduce){*{scroll-behavior:auto}}
</style>
