<script lang="ts" module>
 const restored = new WeakMap<object,Map<string,string>>();
</script>
<script lang="ts">
 import {onMount} from 'svelte';
 import Hero from './Hero.svelte';
 import type {Item} from '../api/types';
 import {session} from '../stores/session.svelte';
 import {playerHref} from '../player/route';
 import {t} from '../i18n';
 let {items, subtitles=new Map<string,string>()}: {items:Item[];subtitles?:Map<string,string>}=$props();
 let id=$state(''), reduced=$state(false), indicators=$state(false);
 let root=$state<HTMLElement>();
 const active=$derived(items.find(i=>i.id===id)??items[0]);
 const index=$derived(items.findIndex(i=>i.id===active?.id));
 let last=Date.now(), input=0, indicator:ReturnType<typeof setTimeout>;
 function note(){input=Date.now();last=input+8000}
 function move(next:number,manual=true){if(next<0||next>=items.length)return;id=items[next]!.id;let saved=restored.get(session.client);if(!saved){saved=new Map();restored.set(session.client,saved)}saved.set(session.me?.id??'',id);if(manual){note();indicators=true;clearTimeout(indicator);indicator=setTimeout(()=>indicators=false,2000)}else last=Date.now()}
 onMount(()=>{
  const media=typeof matchMedia==='function'?matchMedia('(prefers-reduced-motion: reduce)'):null;reduced=media?.matches??false;
  id=restored.get(session.client)?.get(session.me?.id??'')??'';
  const motion=()=>reduced=media?.matches??false;media?.addEventListener('change',motion);
  let foreground=true;const blur=()=>foreground=false;const focus=()=>{foreground=true;last=Date.now()};
  document.addEventListener('pointerdown',note);document.addEventListener('keydown',note);window.addEventListener('blur',blur);window.addEventListener('focus',focus);
  const timer=setInterval(()=>{const paused=!foreground||document.hidden||reduced||(root?.getBoundingClientRect().top ?? 0) < -20||document.activeElement?.closest('.home')||document.querySelector('dialog[open],.consumer-sidebar:not(.consumer-sidebar--compact)');if(paused){last=Date.now();return}if(items.length>1&&Date.now()-input>=8000&&Date.now()-last>=8000)move((index+1)%items.length,false)},200);
  return()=>{clearInterval(timer);clearTimeout(indicator);media?.removeEventListener('change',motion);document.removeEventListener('pointerdown',note);document.removeEventListener('keydown',note);window.removeEventListener('blur',blur);window.removeEventListener('focus',focus)};
 });
 let start=0;
</script>
{#if active}
 <section class="billboard" bind:this={root} aria-label={t('hero.featured')}
 ontouchstart={e=>start=e.touches[0]?.clientX??0} ontouchend={e=>{const dx=(e.changedTouches[0]?.clientX??start)-start;if(Math.abs(dx)>50)move(index+(dx<0?1:-1))}}>
 <div class="slide"><Hero cinema billboard item={active} subtitle={subtitles.get(active.id)} summary={active.summary??undefined} playHref={session.capabilities?.playback_plan===true&&(active.kind==='movie'||active.kind==='episode')&&(active.versions?.length??0)>0?playerHref(active.id,active.user_state?.watched?0:active.user_state?.position_ms):undefined}/></div>
 {#if items.length>1}<div class="controls"><div class="segments" class:visible={indicators} aria-hidden="true">{#each items as item}<b class:active={item.id===active.id}></b>{/each}</div><button aria-label={t('hero.previous')} disabled={index===0} onclick={()=>move(index-1)}>‹</button><button aria-label={t('hero.next')} disabled={index===items.length-1} onclick={()=>move(index+1)}>›</button></div>{/if}
 </section>
{/if}
<style>
.billboard{position:relative;isolation:isolate;height:calc(100svh - 186px);min-height:360px}.slide{position:absolute;inset:0}.controls{position:absolute;right:26px;bottom:26px;display:flex;gap:6px;align-items:center;z-index:2}button{height:36px;width:36px;border-radius:50%;border:1px solid var(--hairline);color:var(--ink);background:color-mix(in srgb,var(--bg) 40%,transparent);font-size:24px;cursor:pointer}button:disabled{opacity:.35}.segments{display:flex;gap:6px;visibility:hidden}.segments.visible{visibility:visible}.segments b{height:3px;width:18px;background:color-mix(in srgb,var(--ink) 34%,transparent)}.segments b.active{background:var(--ink)}@media(max-width:899px){.billboard{height:calc(100svh - 250px);min-height:490px}.controls{bottom:0}}
</style>
