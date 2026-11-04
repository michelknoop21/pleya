<script lang="ts">
  import { untrack } from 'svelte';
  import { adminSettingsApi } from '../../api/adminSettings';
  import { ApiError } from '../../api/errors';
  import type { Artwork, ArtworkCandidate, ArtworkCandidates, ArtworkSelection, ArtworkSelectionRequest } from '../../api/types';
  import ArtworkImage from '../../components/Artwork.svelte';
  import Alert from '../../components/Alert.svelte';
  import Panel from '../../components/Panel.svelte';
  import SkeletonPage from '../../components/SkeletonPage.svelte';
  import { session } from '../../stores/session.svelte';
  import { t } from '../../i18n';
  import ArtworkChoicePreview from './ArtworkChoicePreview.svelte';
  import ArtworkCredits from './ArtworkCredits.svelte';

  type Role='poster'|'backdrop';
  let {itemId, defaultArtwork}: {itemId:string; defaultArtwork?:Artwork}=$props();
  const roles:Role[]=['poster','backdrop'];
  const allowed=$derived(session.canAdminister===true && session.capabilities?.artwork_choices===true);
  let data=$state<ArtworkCandidates|null>(null);
  let defaults=$state<Artwork|undefined>();
  let picks=$state<Partial<Record<Role,ArtworkCandidate>>>({});
  let loading=$state(false);let writing=$state(false);
  let failure=$state<string|null>(null);let notice=$state<string|null>(null);
  let needsReload=$state(false);let attempt=$state(0);
  const dirty=$derived(Boolean(picks.poster||picks.backdrop));
  const busy=$derived(loading||writing);
  let sequence=0;
  // Retry intent belongs to this item/account context, not to candidate state.
  let defaultRefreshNeeded=false;
  let writeController:AbortController|null=null;
  let previous:{id:string;client:typeof session.client;generation:number;subject:string|undefined;allowed:boolean}|null=null;
  const label=(role:Role)=>t(role==='poster'?'admin.metadata.artwork.poster':'admin.metadata.artwork.backdrop');
  const source=(name:string)=>t(name==='tmdb'?'admin.metadata.artwork.source.tmdb':name==='local'?'admin.metadata.artwork.source.local':'admin.metadata.artwork.source.unknown');
  const valid=(value:ArtworkSelection,id:string)=>value.item_id===id && /^[a-f0-9]{64}$/.test(value.base_token) && value.pins && 'poster' in value.pins && 'backdrop' in value.pins;
  function current(id:string,client:typeof session.client,generation:number,subject:string|undefined,own:number):boolean {
    return own===sequence && id===itemId && client===session.client && generation===client.sessionGeneration && subject===session.me?.id && allowed;
  }
  function errorMessage(error:unknown):string {
    return t(error instanceof ApiError && error.status===429 ? 'admin.metadata.artwork.rate'
      : error instanceof ApiError && error.code==='library.artwork_stale' ? 'admin.metadata.artwork.stale'
      : error instanceof ApiError && error.code==='library.artwork_source_changed' ? 'admin.metadata.artwork.sourceChanged'
      : error instanceof ApiError && error.code==='library.artwork_source_unavailable' ? 'admin.metadata.artwork.unavailable'
      : 'admin.metadata.artwork.failed');
  }
  $effect(()=>{
    void attempt;
    const id=itemId, client=session.client, generation=client.sessionGeneration, subject=session.me?.id, enabled=allowed;
    const own=++sequence;const controller=new AbortController();
    const changed=!previous||previous.id!==id||previous.client!==client||previous.generation!==generation||previous.subject!==subject||previous.allowed!==enabled;
    previous={id,client,generation,subject,allowed:enabled};
    untrack(()=>{
      writeController?.abort();writing=false;failure=null;notice=null;
      if(changed){data=null;picks={};defaults=defaultArtwork;needsReload=false;defaultRefreshNeeded=false;}
      loading=enabled;
    });
    if(enabled) adminSettingsApi(client).artworkCandidates(id,controller.signal).then(async result=>{
      if(controller.signal.aborted||!current(id,client,generation,subject,own))return;
      if(!valid(result,id))throw new Error('artwork item mismatch');
      data=result;picks={};needsReload=false;
      if(defaultRefreshNeeded)await refreshDefault(id,client,generation,subject,own,controller);
    }).catch(error=>{if(!controller.signal.aborted&&current(id,client,generation,subject,own))failure=errorMessage(error);})
      .finally(()=>{if(current(id,client,generation,subject,own))loading=false;});
    return()=>{controller.abort();writeController?.abort();};
  });
  async function refreshDefault(id:string,client:typeof session.client,generation:number,subject:string|undefined,own:number,controller:AbortController):Promise<void>{
    try{
      const item=await client.item(id,controller.signal);
      if(controller.signal.aborted||!current(id,client,generation,subject,own))return;
      if(item.id!==id)throw new Error('artwork item mismatch');
      defaults=item.artwork;defaultRefreshNeeded=false;
    }catch{if(!controller.signal.aborted&&current(id,client,generation,subject,own))failure=t('admin.metadata.artwork.loadDefault');}
  }
  function selectable(candidate:ArtworkCandidate):boolean {
    return candidate.available && (candidate.role==='poster'||candidate.role==='backdrop') &&
      /^[a-f0-9]{64}$/.test(candidate.id) &&
      (candidate.source==='local' ? Boolean(candidate.artwork_id) : candidate.source==='tmdb' && Boolean(candidate.preview_ref?.match(/^\/[A-Za-z0-9_-]{1,200}\.(jpg|png|webp)$/)));
  }
  function choose(candidate:ArtworkCandidate):void {
    if(!allowed||busy||needsReload||!selectable(candidate))return;
    picks={...picks,[candidate.role]:candidate};failure=null;notice=null;
  }
  async function save(unpin?:Role):Promise<void>{
    if(!allowed||busy||!data||(unpin?dirty||!data.pins[unpin]:!dirty||needsReload))return;
    const id=itemId,client=session.client,generation=client.sessionGeneration,subject=session.me?.id,own=sequence;
    const controller=new AbortController();writeController=controller;
    const body:ArtworkSelectionRequest={base_token:data.base_token};
    if(unpin)body[unpin]=null;else for(const role of roles)if(picks[role])body[role]=picks[role]!.id;
    writing=true;failure=null;notice=null;
    try{
      const result=await adminSettingsApi(client).setArtwork(id,body,controller.signal);
      if(controller.signal.aborted||!current(id,client,generation,subject,own))return;
      if(!valid(result,id) || (unpin?result.pins[unpin]!==null:roles.some(role=>picks[role]&&!result.pins[role])))throw new Error('artwork confirmation mismatch');
      data={...data,...result,candidates:[]};picks={};needsReload=true;
      notice=unpin?t('admin.metadata.artwork.unpinned',{role:label(unpin)}):t('admin.metadata.artwork.saved');
      if(unpin){
        defaults=undefined;
        defaultRefreshNeeded=true;
        await refreshDefault(id,client,generation,subject,own,controller);
      }
    }catch(error){if(!controller.signal.aborted&&current(id,client,generation,subject,own))failure=errorMessage(error);}
    finally{if(current(id,client,generation,subject,own))writing=false;}
  }
</script>

{#if allowed}
<div id="artwork" class="artwork-editor">
  <Panel level={2}>
    {#snippet title()}{t('admin.metadata.artwork.title')}{/snippet}
    <p class="intro">{t('admin.metadata.artwork.intro')}</p>
    {#if failure}<Alert tone="err">{failure}</Alert>{/if}
    {#if notice}<Alert tone="info">{notice}</Alert>{/if}
    {#if data}
      {#if data.provider_state==='not_configured'}<p class="help">{t('admin.metadata.artwork.keyless')}</p>
      {:else if data.provider_state==='identity_unknown'}<p class="help">{t('admin.metadata.artwork.unknown')}</p>
      {:else if data.provider_state!=='available'}<p class="help">{t('admin.metadata.artwork.providerError')}</p>{/if}
      {#each roles as role (role)}
        {@const pin=data.pins[role]}
        {@const candidates=data.candidates.filter(candidate=>candidate.role===role).slice(0,20)}
        <section class="role" aria-label={label(role)}>
          <header><h3>{label(role)}</h3><span class:pinned={Boolean(pin)}>{t(pin?'admin.metadata.artwork.pinned':'admin.metadata.artwork.default')}{#if pin} · {source(pin.source)}{/if}</span></header>
          {#if pin && pin.state!=='ready'}<Alert tone="warn">{t(pin.error_code==='source_changed'?'admin.metadata.artwork.sourceChanged':'admin.metadata.artwork.unavailable')}</Alert>{/if}
          <div class:wide={role==='backdrop'} class="role-content">
            <div class="preview">
              {#if picks[role]}
                {#key picks[role]!.id}<ArtworkChoicePreview {itemId} candidate={picks[role]!}/>{/key}
                <p class="help" role="status">{t('admin.metadata.artwork.pending')}</p>
              {:else}
                <ArtworkImage artworkId={pin?.artwork_id??(role==='poster'?defaults?.poster_id:defaults?.backdrop_id)} alt={t('admin.metadata.artwork.current')} shape={role==='poster'?'poster':'wide'} />
              {/if}
            </div>
            <div class="choices">
              {#if candidates.length}
                <fieldset disabled={busy||needsReload}><legend>{label(role)}</legend>
                  {#each candidates as candidate,index (candidate.id)}
                    <label class:selected={picks[role]?.id===candidate.id} class:unavailable={!selectable(candidate)}>
                      <input type="radio" name={itemId+'-'+role} value={candidate.id} checked={picks[role]?.id===candidate.id} disabled={!selectable(candidate)} onchange={()=>choose(candidate)}/>
                      <span><strong>{t('admin.metadata.artwork.choose',{role:label(role).toLowerCase(),number:index+1})}</strong><small>{source(candidate.source)} · {candidate.language?t('admin.metadata.artwork.language',{language:candidate.language}):t('admin.metadata.artwork.neutral')}</small></span>
                    </label>
                  {/each}
                </fieldset>
              {:else}<p class="help">{t(needsReload?'admin.metadata.artwork.refreshHint':'admin.metadata.artwork.empty')}</p>{/if}
              {#if pin}<button class="btn btn--secondary btn--sm" disabled={busy||dirty} onclick={()=>void save(role)}>{t('admin.metadata.artwork.unpin',{role:label(role)})}</button>{/if}
            </div>
          </div>
        </section>
      {/each}
      <div class="actions">
        <button class="btn" disabled={busy||!dirty||needsReload} onclick={()=>void save()}>{t(writing?'admin.metadata.artwork.saving':'admin.metadata.artwork.save')}</button>
        <button class="btn btn--secondary" disabled={busy||!dirty} onclick={()=>{picks={};failure=null;notice=null;}}>{t('admin.metadata.artwork.reset')}</button>
        <button class="text-action" disabled={busy||dirty} onclick={()=>attempt++}>{t('admin.metadata.artwork.reload')}</button>
      </div>
      {#if dirty}<p class="help">{t('admin.metadata.artwork.dirtyHint')}</p>{/if}
      {#if data.candidates.some(candidate=>candidate.source==='tmdb')||roles.some(role=>data?.pins[role]?.source==='tmdb')}
        <p class="help">{t('admin.metadata.artwork.creditHint')}</p><ArtworkCredits/>
      {/if}
    {:else if loading}<SkeletonPage variant="compact"/>
    {:else}<button class="btn btn--secondary" onclick={()=>attempt++}>{t('admin.metadata.artwork.reload')}</button>{/if}
  </Panel>
</div>
{/if}
<style>
  .artwork-editor { margin-top:24px; min-width:0; scroll-margin-top:90px; }
  .intro { color:var(--ink-2); max-width:65ch; line-height:1.5; margin:0 0 20px; }
  .role { padding:20px 0; border-top:1px solid var(--hairline); min-width:0; }
  .role header { display:flex; justify-content:space-between; align-items:baseline; gap:12px; margin-bottom:14px; flex-wrap:wrap; }
  .role h3 { font-size:16px; margin:0; }
  .role header span { font-size:12px; color:var(--ink-3); }
  .role header .pinned { color:var(--ink); font-weight:600; }
  .role-content { display:grid; grid-template-columns:160px minmax(0,1fr); gap:24px; margin-top:14px; align-items:start; }
  .role-content.wide { grid-template-columns:minmax(0,1fr); }
  .wide .preview { max-width:560px; }
  .preview { min-width:0; }
  .choices { min-width:0; display:grid; gap:14px; }
  fieldset { display:grid; gap:8px; padding:0; border:0; margin:0; max-height:320px; overflow-y:auto; }
  legend { position:absolute; width:1px; height:1px; overflow:hidden; clip-path:inset(50%); }
  fieldset label { display:flex; gap:10px; align-items:center; padding:12px; min-height:58px; background:var(--panel-2); border:1px solid var(--hairline); border-radius:10px; cursor:pointer; }
  fieldset label.selected { border-color:var(--accent); }
  fieldset label:focus-within { outline:2px solid var(--accent); outline-offset:2px; }
  input { accent-color:var(--accent); flex:none; }
  label span { display:grid; gap:4px; min-width:0; overflow-wrap:anywhere; }
  label strong { font-size:13px; font-weight:600; }
  label small,.help { color:var(--ink-2); font-size:12px; line-height:1.5; }
  .help { margin:12px 0; }
  label.unavailable { opacity:.5; cursor:default; }
  .actions { display:flex; align-items:center; flex-wrap:wrap; gap:12px; padding-top:20px; border-top:1px solid var(--hairline-strong); }
  .text-action { min-height:44px; border:0; background:none; color:var(--ink-2); text-decoration:underline; text-underline-offset:3px; cursor:pointer; }
  .text-action:disabled { opacity:.5; cursor:default; }
  @media(max-width:540px) { .role-content { grid-template-columns:minmax(0,1fr); gap:16px; } .role-content:not(.wide) .preview { max-width:180px; } .actions { align-items:stretch; flex-direction:column; } .actions button { width:100%; } fieldset { max-height:265px; } }
</style>
