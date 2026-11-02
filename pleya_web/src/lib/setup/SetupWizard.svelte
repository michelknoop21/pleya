<script lang="ts">
 import ScanPreview from './ScanPreview.svelte';
 import { page } from '$app/state';
 import { goto } from '$app/navigation';
 import { untrack } from 'svelte';
 import { session } from '#lib/stores/session.svelte.js';
 import { adminApi } from '#lib/api/admin.js';
 import { describeError } from '#lib/api/errors.js';
 import type { Library } from '#lib/api/types.js';
 import Field from '#lib/components/Field.svelte';
 import Alert from '#lib/components/Alert.svelte';
 import Panel from '#lib/components/Panel.svelte';
 import ConfirmDialog from '#lib/components/ConfirmDialog.svelte';
 import SkeletonPage from '#lib/components/SkeletonPage.svelte';
 import { t } from '#lib/i18n/index.js';
 import { readSetup, setupStage, availableRoots, type SetupSnapshot } from './setup';
 let {onstep}:{onstep:(step:number)=>void}=$props();
 let data=$state<SetupSnapshot|null>(null);
 let problem=$state<string|null>(null);
 let busy=$state(false);
 let draft=$state(false);
 let selected=$state<string[]>([]);
 let title=$state('');
 let kind=$state<'movies'|'shows'>('movies');
 let confirm=$state<Library|null>(null);
 let attempt=$state(0);
 let sequence=0;
 const account=$derived(`${session.client.sessionGeneration}:${session.me?.id}:${session.canAdminister}`);
 const stage=$derived(data ? (setupStage(data)===1 && draft ? 2 : setupStage(data)) : 1);
 const configs=$derived(data?.libraries.filter(l=>l.managed==='config')??[]);
 const libraries=$derived(data?.libraries??[]);
 const missingRoots=$derived(data?.roots.filter(r=>!r.mounted && r.libraries.some(ref=>libraries.some(l=>l.id===ref.id)))??[]);
 function missingFor(id:string){return missingRoots.some(r=>r.libraries.some(l=>l.id===id));}
 const active=$derived(libraries.some(l=>['queued','running'].includes(data?.scans[l.id]?.state??'')));
 function context() {
  const client=session.client;const generation=client.sessionGeneration;const subject=session.me?.id;
  return {client,current:()=>client===session.client && generation===client.sessionGeneration && subject===session.me?.id && session.canAdminister};
 }
 async function refresh(signal?:AbortSignal) {
  const c=context();if(!c.current())return;
  const seq=++sequence;
  try {
   const result=await readSetup(c.client,signal);
   if(!c.current() || signal?.aborted || seq!==sequence)return;
   data=result;problem=null;
   selected=selected.filter(path=>availableRoots(result).some(r=>r.path===path));
   if(!draft && page.url.searchParams.get('draft')==='library' && result.libraries.length===0) {
    selected=page.url.searchParams.getAll('root').filter(path=>availableRoots(result).some(r=>r.path===path));
    draft=selected.length>0;
   }
  }catch(error){if(c.current() && !signal?.aborted && seq===sequence)problem=describeError(error);}
 }
 $effect(()=>{
  void account;void attempt;
  const controller=new AbortController();
  untrack(()=>{sequence++;data=null;problem=null;busy=false;confirm=null;draft=false;selected=[];title='';void refresh(controller.signal);});
  return()=>{controller.abort();sequence++;};
 });
 $effect(()=>{onstep(stage);});
 $effect(()=>{
  if(!active || problem || busy)return;
  const timer=setInterval(()=>{void refresh();},3000);
  return()=>clearInterval(timer);
 });
 async function chooseRoots() {
  if(!data || busy || !session.canAdminister)return;
  const c=context();
  selected=selected.filter(p=>availableRoots(data!).some(r=>r.path===p));
  if(!selected.length)return;
  const query=new URLSearchParams({draft:'library'});selected.forEach(p=>query.append('root',p));
  busy=true;
  try {
   await goto(`/setup?${query}`,{replace:true,reset:false});
   if(c.current())draft=true;
  } catch(error) {if(c.current())problem=describeError(error);}
  finally {if(c.current())busy=false;}
 }
 async function backRoots() {
  if(busy || !session.canAdminister)return;
  const c=context();busy=true;
  try {await goto('/setup',{replace:true,reset:false});if(c.current())draft=false;}
  catch(error){if(c.current())problem=describeError(error);}
  finally{if(c.current())busy=false;}
 }
 async function act(action:(c:ReturnType<typeof context>)=>Promise<void>) {
  if(busy || !session.canAdminister)return;
  const c=context();busy=true;problem=null;
  try{await action(c);if(c.current()){await refresh();if(c.current())await session.load();}}
  catch(error){if(c.current()){await refresh();if(c.current())problem=describeError(error);}}
  finally{if(c.current())busy=false;}
 }
 async function create() {
  await act(async(c)=>{
   const fresh=await readSetup(c.client);if(!c.current())return;
   // A lost create response or another tab may already have persisted step 3.
   if(fresh.libraries.length){data=fresh;return;}
   const roots=selected.filter(p=>availableRoots(fresh).some(r=>r.path===p));
   if(roots.length!==selected.length || !roots.length)throw new Error(t('setup.rootsChanged'));
   await adminApi(c.client).createLibrary({title:title.trim(),kind,root_paths:roots,scan_on_start:true});
   if(c.current())await goto('/setup',{replace:true,reset:false});
  });
 }
 async function adopt() {
  const library=confirm;if(!library)return;
  confirm=null;
  await act(async(c)=>{
   const fresh=await readSetup(c.client);if(!c.current())return;
   if(fresh.libraries.some(l=>l.id===library.id && l.managed==='config'))await adminApi(c.client).adoptLibrary(library.id);
  });
 }
 async function scanLibrary(id:string) {
  await act(async(c)=>{
   const fresh=await readSetup(c.client);if(!c.current())return;
   const latest=fresh.scans[id];
   if(fresh.roots.some(r=>!r.mounted && r.libraries.some(l=>l.id===id)))throw new Error(t('setup.missingSavedRoot'));
   if(!fresh.libraries.some(l=>l.id===id) || latest?.state==='done' || latest?.state==='queued' || latest?.state==='running'){data=fresh;return;}
   await adminApi(c.client).startScan(id);
  });
 }
</script>
{#if problem}<div class="error"><Alert tone="err">{problem}</Alert><button class="btn btn--secondary" disabled={busy} onclick={()=>{void refresh();}}>{t('setup.retryRead')}</button></div>{/if}
{#if !data}
 {#if !problem}<SkeletonPage variant="compact" />{/if}
{:else if stage===1}
 <h1>{t('setup.storageTitle')}</h1><p class="intro">{t('setup.storageIntro')}</p>
 <fieldset disabled={busy}><legend class="visually-hidden">{t('setup.storageStep')}</legend>
 {#each data.roots as root (root.path)}
  <label class="choice" class:chosen={selected.includes(root.path)}>
   <input type="checkbox" value={root.path} bind:group={selected} disabled={!root.mounted || root.libraries.length>0} />
   <span class="body"><span class="mono">{root.path}</span><small>{root.mounted?t('setup.mounted'):t('setup.unmounted')}{root.fs_type?` · ${root.fs_type}`:''}</small></span>
  </label>
 {/each}
 </fieldset>
 {#if !data.roots.length}<Alert tone="warn">{t('setup.noRoots')}</Alert>{/if}
 <p class="help">{t('setup.mountHelp')}</p>
 <div class="foot"><button class="btn btn--secondary" disabled={busy} onclick={()=>{void refresh();}}>{t('setup.retryRead')}</button><button class="btn" disabled={busy||!selected.length} onclick={chooseRoots}>{t('setup.next')}</button></div>
{:else if stage===2 && configs.length}
 <h1>{t('setup.adoptTitle')}</h1><p class="intro">{t('setup.adoptIntro')}</p>
 {#each configs as library (library.id)}
  <div class="existing"><strong>{library.title}</strong><span>{t(library.kind==='shows'?'nav.series':'nav.films')}</span><button class="btn btn--secondary" disabled={busy} onclick={()=>confirm=library}>{t('setup.adopt')}</button></div>
 {/each}
 <div class="foot"><a class="btn btn--secondary" href="/admin/libraries">{t('setup.manage')}</a></div>
{:else if stage===2}
 <h1>{t('setup.libraryTitle')}</h1><p class="intro">{t('setup.libraryIntro')}</p>
 <form onsubmit={(event)=>{event.preventDefault();if(title.trim()&&selected.length)void create();}}>
 <fieldset disabled={busy}><legend>{t('setup.kind')}</legend><div class="kinds">
  <label class="choice" class:chosen={kind==='movies'}><input type="radio" value="movies" bind:group={kind} /><strong>{t('nav.films')}</strong></label>
  <label class="choice" class:chosen={kind==='shows'}><input type="radio" value="shows" bind:group={kind} /><strong>{t('nav.series')}</strong></label>
 </div>
 <div class="name"><Field label={t('setup.libraryName')} bind:value={title} required /></div>
 <p class="help">{t('setup.selectedRoots')}</p>{#each selected as path}<p class="mono path">{path}</p>{/each}
 </fieldset>
 <div class="foot"><button class="btn btn--secondary" type="button" disabled={busy} onclick={()=>void backRoots()}>{t('setup.back')}</button><button class="btn" disabled={busy||!title.trim()||!selected.length}>{busy?t('loading'):t('setup.createLibrary')}</button></div>
 </form>
{:else}
 <h1>{missingRoots.length?t('setup.storageCheckTitle'):active?t('setup.scanningTitle'):libraries.every(l=>data!.scans[l.id]?.state==='done')?t('setup.scanTitle'):t('setup.scanPendingTitle')}</h1><p class="intro">{t('setup.scanIntro')}</p>
 {#if missingRoots.length}<Alert tone="warn">{t('setup.missingSavedRoot')}{#each missingRoots as root}<p class="mono">{root.path}</p>{/each}</Alert>{/if}
 {#each libraries as library (library.id)}
  {@const scan=data.scans[library.id]}
  <Panel><strong>{library.title}</strong>
   {#if scan?.state==='done'}<p class="status">{t(library.item_count===1?'setup.scanDoneOne':'setup.scanDone',{count:library.item_count})}</p>{#if library.item_count===0}<p class="help">{t('setup.emptyScan')}</p>{/if}
   {:else if scan?.state==='running' || scan?.state==='queued'}<p class="status" role="status">{t('setup.scanRunning',{files:scan.files_seen})}</p>
   {:else if scan?.state==='failed' || scan?.state==='cancelled'}<p class="status">{t('setup.scanFailed')}</p><button class="btn btn--secondary" disabled={busy||missingFor(library.id)} onclick={()=>void scanLibrary(library.id)}>{t('setup.retryScan')}</button>
   {:else}<p class="status">{t('setup.scanNone')}</p><button class="btn" disabled={busy||missingFor(library.id)} onclick={()=>void scanLibrary(library.id)}>{t('setup.startScan')}</button>{/if}
  </Panel>
 {/each}
 {#if libraries[0]}<ScanPreview libraryId={libraries[0].id} revision={data} />{/if}
 <div class="foot"><button class="btn btn--secondary" disabled={busy} onclick={()=>{void refresh();}}>{t('setup.retryRead')}</button><a class="btn" href="/">{t('setup.home')}</a></div>
 <p class="help">{t('setup.moreLibraries')} <a href="/admin/libraries">{t('setup.manage')}</a></p>
{/if}
<ConfirmDialog open={confirm!==null} oncancel={()=>confirm=null} title={t('setup.adopt')} message={t('setup.adoptConfirm',{name:confirm?.title??''})} confirmLabel={t('setup.adopt')} {busy} onconfirm={()=>void adopt()} />
<style>
 h1{font-size:28px;letter-spacing:-.01em;line-height:1.2}.intro{color:var(--ink-2);font-size:15px;line-height:1.45;margin:10px 0 20px}.help{font-size:13px;color:var(--ink-3);line-height:1.5;margin:16px 0}.foot{display:flex;justify-content:space-between;gap:12px;align-items:center;margin:28px 0 0}.choice{display:flex;align-items:center;gap:14px;padding:16px;border:1px solid transparent;border-radius:12px;background:var(--panel);margin:10px 0;cursor:pointer}.chosen{border-color:var(--ink)}.body{min-width:0;display:grid;gap:5px}.mono{font-family:var(--font-mono);overflow-wrap:anywhere;font-size:14px}small{color:var(--ink-3);font-size:13px}input{accent-color:var(--ink);width:20px;height:20px;flex:none}fieldset{padding:0;margin:0;border:0;min-width:0}legend{font-size:13px;color:var(--ink-2)}.kinds{display:grid;grid-template-columns:1fr 1fr;gap:10px}.name{margin-top:16px}.existing{display:flex;align-items:center;gap:12px;flex-wrap:wrap;padding:16px;border:1px solid var(--hairline);border-radius:12px;margin:12px 0}.existing span{color:var(--ink-3);font-size:13px}.existing button{margin-left:auto}.path{margin:8px 0}.status{margin:12px 0}.error{margin-bottom:20px;display:grid;gap:12px}@media(max-width:599px){.kinds{grid-template-columns:1fr}.foot .btn{flex:1;text-align:center}.foot{align-items:stretch}.existing button{width:100%;margin:0}}
</style>
