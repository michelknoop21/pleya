<script lang="ts">
  import { adminSettingsApi } from '../../api/adminSettings';
  import { ApiError, describeError } from '../../api/errors';
  import { untrack } from 'svelte';
  import type { MetadataAttentionList, MetadataMatchStatus } from '../../api/types';
  import AdminIcon from '../../components/AdminIcon.svelte';
  import Alert from '../../components/Alert.svelte';
  import ConfirmDialog from '../../components/ConfirmDialog.svelte';
  import SkeletonPage from '../../components/SkeletonPage.svelte';
  import StateView from '../../components/StateView.svelte';
  import { t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import AdminPageHead from '../AdminPageHead.svelte';
  import LibraryProblemAlert from '../LibraryProblemAlert.svelte';
  import type { LibraryProblem } from '../libraryErrors';
  import CandidatePanel from './CandidatePanel.svelte';
  import MatchList from './MatchList.svelte';
  import MatchSide from './MatchSide.svelte';
  import { loadMatch, sortedAttention, titleOf, type MatchTarget } from './match';
  import { matchProblem } from './matchErrors';

  let { initialItem = null }: { initialItem?: string | null } = $props();

  let data = $state<MetadataAttentionList | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);
  // De link vanaf scherm 29 zet de beginkeuze; daarna beslist de bezoeker.
  // svelte-ignore state_referenced_locally
  let selected = $state<string | null>(initialItem);
  let problem = $state<LibraryProblem | null>(null);
  let retry = $state<() => void>(() => {});
  let notice = $state<string | null>(null);
  // Local receipt of PUT202, independent of the attention wire state and application status.
  let receivedFor = $state<string | null>(null);
  let receipt = $state<{itemId:string; externalId:string; previousGeneration:string | null} | null>(null);
  // A2 generations retain nanoseconds. Date is used only for whole seconds/timezone;
  // comparing Date milliseconds alone would collapse consecutive microgenerations.
  function generationAfter(value:string | null, previous:string | null): boolean {
    function instant(raw:string | null): bigint | null {
      const parts=raw?.match(/^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,9}))?(Z|[+-]\d{2}:\d{2})$/);
      if(!parts) return null;
      const whole=Date.parse(parts[1]!+parts[3]!);
      return Number.isFinite(whole) ? BigInt(whole)*1_000_000n+BigInt((parts[2]??'').padEnd(9,'0')) : null;
    }
    const current=instant(value);const before=instant(previous);
    return current!==null && (previous===null || (before!==null && current>before));
  }
  let busy = $state(false);
  /** De keuze die op een bevestiging wacht. */
  let pending = $state<{ item: MatchTarget; externalId: string; label: string; client: typeof session.client; generation: number; subject: string | undefined } | null>(null);
  let rejectedItem = $state<{item:MatchTarget; client:typeof session.client; generation:number; subject:string | undefined} | null>(null);
  let retained = $state<MatchTarget | null>(null);
  let status = $state<MetadataMatchStatus | null>(null);
  let statusFailure = $state(false);
  let statusBusy = $state(false);
  let statusAttempt = $state(0);
  let statusController: AbortController | null = null;
  let statusSequence = 0;
  const statusEnabled = $derived(session.capabilities?.metadata_match_status === true);
  const accountContext = $derived(`${session.client.sessionGeneration}:${session.me?.id ?? ''}:${session.canAdminister}`);
  function sameAccount(client: typeof session.client, generation: number, subject: string | undefined): boolean {
    return client === session.client && generation === client.sessionGeneration && subject === session.me?.id && session.canAdminister !== false;
  }
  let pickOpen = $state(false);
  let rejectOpen = $state(false);

  $effect(() => {
    void attempt; void accountContext;
    const controller = new AbortController();
    const client = session.client; const generation = client.sessionGeneration; const subject = session.me?.id;
    if (session.canAdminister === false) { data=null; retained=null; status=null; pending=null; receivedFor=null; receipt=null; pickOpen=false; rejectOpen=false; return; }
    loadMatch(adminSettingsApi(client), controller.signal)
      .then((result) => {
        if (controller.signal.aborted || !sameAccount(client,generation,subject)) return;
        data = result; failure = null;
      })
      .catch((err: unknown) => {
        if (controller.signal.aborted || !sameAccount(client,generation,subject)) return;
        if (data) problem = matchProblem(err, ''); else failure = describeError(err);
      });
    return () => controller.abort();
  });
  $effect(() => {
    void accountContext;
    untrack(() => { data=null; retained=null; status=null; pending=null; receivedFor=null; receipt=null; rejectedItem=null; pickOpen=false; rejectOpen=false; busy=false; problem=null; notice=null; });
  });

  const items = $derived(data ? sortedAttention(data.items) : []);
  // Zonder gekozen titel (of een die niet meer op de lijst staat) valt de keuze op de eerste.
  const current = $derived(items.find((i) => i.item_id === selected) ?? (retained?.item_id === selected ? retained : null));
  const gone = $derived(Boolean(data && selected && !current));
  const shown = $derived(current ?? (gone ? null : (items[0] ?? null)));
  const shownItemId = $derived(shown?.item_id ?? null);

  // Existing items outside the attention list remain addressable by their item deep link.
  $effect(() => {
    const id=selected; const client=session.client; const generation=client.sessionGeneration; const subject=session.me?.id;
    if (!data || !id || current || session.capabilities?.metadata_search!==true || session.canAdminister===false) return;
    const controller=new AbortController();
    client.item(id,controller.signal).then(item=>{
      if(controller.signal.aborted || selected!==id || !sameAccount(client,generation,subject) || (item.kind!=='movie' && item.kind!=='show')) return;
      retained={item_id:item.id,kind:item.kind,title:item.title,year:item.year ?? null,state:'unknown',alternatives:[]};
    }).catch(()=>{});
    return ()=>controller.abort();
  });
  function stopStatus(): void { statusController?.abort(); statusSequence++; statusBusy=false; }
  $effect(() => {
    void shownItemId;
    untrack(()=>{stopStatus(); status=null; statusFailure=false; pending=null; receivedFor=null; receipt=null; rejectedItem=null; pickOpen=false; rejectOpen=false;});
  });
  $effect(() => {
    void statusAttempt; void accountContext;
    const id=shown?.item_id; const client=session.client; const generation=client.sessionGeneration; const subject=session.me?.id;
    if(!id || !statusEnabled || session.canAdminister===false) {status=null;return;}
    const controller=new AbortController(); statusController=controller; const seq=++statusSequence;
    statusBusy=true; statusFailure=false;
    adminSettingsApi(client).metadataMatchStatus(id,controller.signal).then(result=>{
      if(controller.signal.aborted || seq!==statusSequence || shown?.item_id!==id || !sameAccount(client,generation,subject)) return;
      if(result.item_id!==id) throw new Error('status item mismatch');
      status=result;
      const received=receipt;
      if(received?.itemId===id && String(result.requested_external_ids?.tmdb)===received.externalId &&
        (result.application_state==='failed' || (result.application_state==='applied' && String(result.applied_external_ids?.tmdb)===received.externalId)) &&
        generationAfter(result.updated_at,received.previousGeneration)) {
        notice=null;receipt=null;
      }
    }).catch(()=>{
      if(!controller.signal.aborted && seq===statusSequence && shown?.item_id===id && sameAccount(client,generation,subject)) statusFailure=true;
    }).finally(()=>{if(seq===statusSequence && sameAccount(client,generation,subject)) statusBusy=false;});
    return ()=>controller.abort();
  });
  function reload(): void { problem = null; attempt += 1; }
  function askPick(externalId: string, label: string): void {
    if(!shown || busy || session.canAdminister===false) return;
    pending={item:shown,externalId,label,client:session.client,generation:session.client.sessionGeneration,subject:session.me?.id}; pickOpen=true;
  }
  function askReject(): void {if(shown && !busy && session.canAdminister!==false){rejectedItem={item:shown,client:session.client,generation:session.client.sessionGeneration,subject:session.me?.id};rejectOpen=true;}}
  async function pick(): Promise<void> {
    const choice=pending;
    if(!choice || !sameAccount(choice.client,choice.generation,choice.subject) || busy || shown?.item_id!==choice.item.item_id) return;
    const previousGeneration=status?.item_id===choice.item.item_id ? status.updated_at : null;
    const title=titleOf(choice.item); busy=true; problem=null; notice=null; receipt=null; stopStatus();
    try {
      await adminSettingsApi(choice.client).setMetadataMatch(choice.item.item_id,choice.externalId);
      if(!sameAccount(choice.client,choice.generation,choice.subject) || shown?.item_id!==choice.item.item_id) return;
      pickOpen=false; retained=choice.item; selected=choice.item.item_id; receivedFor=choice.item.item_id;
      receipt={itemId:choice.item.item_id,externalId:choice.externalId,previousGeneration};
      notice=t('admin.match.status.received',{title,candidate:choice.label});
      status=null; statusAttempt+=1; attempt+=1;
    } catch(err) {
      if(!sameAccount(choice.client,choice.generation,choice.subject) || shown?.item_id!==choice.item.item_id) return;
      pickOpen=false;problem=matchProblem(err,title);retry=()=>askPick(choice.externalId,choice.label);
      if(err instanceof ApiError && err.status===404) attempt+=1;
    } finally {if(sameAccount(choice.client,choice.generation,choice.subject)) busy=false;}
  }
  async function reject(): Promise<void> {
    const confirmation=rejectedItem;
    if(!confirmation) return;
    const {item,client,generation,subject}=confirmation;
    if(!item || busy || shown?.item_id!==item.item_id || !sameAccount(client,generation,subject)) return;
    const title=titleOf(item);busy=true;problem=null;notice=null;receipt=null;stopStatus();
    try {
      await adminSettingsApi(client).clearMetadataMatch(item.item_id);
      if(!sameAccount(client,generation,subject) || shown?.item_id!==item.item_id) return;
      rejectOpen=false;receivedFor=null; receipt=null;notice=t('admin.match.done.reject',{title});retained=null;attempt+=1;statusAttempt+=1;
    } catch(err) {
      if(!sameAccount(client,generation,subject) || shown?.item_id!==item.item_id) return;
      rejectOpen=false;problem=matchProblem(err,title);retry=()=>askReject();
      if(err instanceof ApiError && err.status===404) attempt+=1;
    } finally {if(sameAccount(client,generation,subject)) busy=false;}
  }
</script>

<AdminPageHead
  title={t('admin.match.title')}
  crumbs={[
    { label: t('admin.title'), href: '/admin' },
    { label: t('admin.nav.metadata'), href: '/admin/metadata' },
    { label: t('admin.match.title') }
  ]}
>
  {#snippet actions()}
    <button type="button" class="btn btn--secondary btn--sm refresh" onclick={reload}>
      <AdminIcon name="refresh" size={16} />{t('admin.match.refresh')}
    </button>
  {/snippet}
</AdminPageHead>

{#if problem}
  <div class="msg">
    <LibraryProblemAlert {problem} onretry={() => retry()} onreload={reload} />
  </div>
{/if}
{#if notice}
  <div class="msg"><Alert tone="info">{notice}</Alert></div>
{/if}

{#if data}
  <div class="match-content">

      {#if gone}
        <Alert tone="info">{t('admin.match.gone')}</Alert>
      {/if}
      {#if shown}
        {#key shown.item_id}<CandidatePanel item={shown} choiceReceived={receivedFor===shown.item_id} {busy} onpick={askPick} onreject={askReject} />{/key}
        <section class="match-status" aria-live="polite" data-generation={status?.updated_at ?? ''}>
          {#if statusEnabled}
            {#if status}
              <strong>{t(status.application_state==='applied' ? 'admin.match.status.applied' : status.application_state==='pending' ? 'admin.match.status.pending' : status.application_state==='failed' ? 'admin.match.status.failed' : 'admin.match.status.unknown')}</strong>
              {#if status.requested_external_ids?.tmdb}<p>{t('admin.match.status.requested',{id:status.requested_external_ids.tmdb})}</p>{/if}
              {#if status.applied_external_ids?.tmdb}<p>{t('admin.match.status.current',{id:status.applied_external_ids.tmdb})}</p>{/if}
              {#if status.application_state==='failed' && status.requested_external_ids?.tmdb}<button class="btn btn--secondary" disabled={busy} onclick={()=>askPick(String(status!.requested_external_ids!.tmdb),t('admin.match.cand.number',{id:status!.requested_external_ids!.tmdb!}))}>{t('admin.match.status.retry')}</button>{/if}
            {/if}
            {#if statusFailure}<Alert tone="err">{t('admin.match.status.unavailable')}</Alert>{/if}
            {#if statusBusy}<p>{t('admin.match.status.loading')}</p><button class="btn btn--secondary" onclick={stopStatus}>{t('admin.match.status.cancel')}</button>{/if}
            <button class="btn btn--secondary" disabled={busy} onclick={()=>{stopStatus();statusAttempt+=1;}}>{t('admin.match.status.refresh')}</button>
          {:else}<p>{t('admin.match.status.legacy')}</p>{/if}
        </section>
      {/if}
      <MatchList list={data!} {items} selected={shown?.item_id ?? null} onselect={(id) => {if(!busy){stopStatus();retained=null;selected=id;notice=null;problem=null;}}} />

      <MatchSide list={data!} />
  </div>

  <ConfirmDialog
    bind:open={pickOpen}
    {busy}
    danger={false}
    title={t('admin.match.confirm.pickTitle')}
    message={t('admin.match.confirm.pickBody', {
      title: pending ? titleOf(pending.item) : '',
      candidate: pending?.label ?? ''
    })}
    confirmLabel={t('admin.match.confirm.pick')}
    onconfirm={() => void pick()}
  />
  <ConfirmDialog
    bind:open={rejectOpen}
    {busy}
    title={t('admin.match.confirm.rejectTitle')}
    message={t('admin.match.confirm.rejectBody', { title: rejectedItem ? titleOf(rejectedItem.item) : '' })}
    confirmLabel={t('admin.match.confirm.reject')}
    onconfirm={() => void reject()}
  />
{:else if failure}
  <StateView kind="error" message={failure} onRetry={() => (attempt += 1)} />
{:else}
  <SkeletonPage variant="compact" />
{/if}

<style>
  .match-content {display:grid;gap:20px;max-width:840px;min-width:0;}
  .match-status { display:grid;gap:10px;margin:0;padding:16px;border:1px solid var(--hairline);border-radius:12px;font-size:14px; }
  .match-status p {margin:0;}
  .match-status .btn {justify-self:start;}
  .msg {
    margin-bottom: 14px;
  }

  @media (max-width: 899px) {
    .refresh {
      justify-content: center;
      width: 100%;
      height: 44px;
    }
  }
</style>
