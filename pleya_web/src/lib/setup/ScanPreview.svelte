<script lang="ts">
 import { session } from '#lib/stores/session.svelte.js';
 import type { Item } from '#lib/api/types.js';
 import MediaCard from '#lib/components/MediaCard.svelte';
 import { t } from '#lib/i18n/index.js';
 let {libraryId,revision}:{libraryId:string;revision:object}=$props();
 let items=$state<Item[]>([]);let failed=$state(false);
 $effect(()=>{
  void revision;
  const client=session.client,generation=client.sessionGeneration,subject=session.me?.id,id=libraryId;
  const controller=new AbortController();
  if(!session.canAdminister)return;
  client.libraryItems(id,{limit:4},controller.signal).then(page=>{
   if(!controller.signal.aborted && client===session.client && generation===client.sessionGeneration && subject===session.me?.id && session.canAdminister){items=page.items;failed=false;}
  }).catch(()=>{if(!controller.signal.aborted){items=[];failed=true;}});
  return()=>controller.abort();
 });
</script>
{#if items.length}<section class="found"><h2>{t('setup.found')}</h2><div class="cards">{#each items as item (item.id)}<MediaCard {item} />{/each}</div></section>{:else if failed}<p class="help">{t('setup.previewUnavailable')}</p>{/if}
<style>.found{margin-top:24px}h2{font-size:16px;margin:0 0 12px}.cards{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:14px}.help{font-size:13px;color:var(--ink-3);margin-top:16px}@media(max-width:599px){.cards{grid-template-columns:repeat(2,minmax(0,1fr))}}</style>
