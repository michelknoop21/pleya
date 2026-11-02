import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { beforeEach, afterEach, expect, it, vi } from 'vitest';
import { tick } from 'svelte';
import { editorSession as session } from './metadata/testing/session.svelte';
import { clientFor, json, apiError } from './libraryFake';
import { job } from './opsFake';
import { setLocale } from '../i18n';
vi.mock('../stores/session.svelte',async()=>({session:(await import('./metadata/testing/session.svelte')).editorSession}));
import StoragePage from './StoragePage.svelte';

beforeEach(()=>{setLocale('nl');session.canAdminister=true;session.capabilities={artwork_cache_admin:true};session.me={id:'admin'};});
afterEach(()=>{setLocale('en');vi.useRealTimers();});
function held<T>(){let resolve!:(value:T)=>void;return {promise:new Promise<T>(r=>resolve=r),resolve:(value:T)=>resolve(value)};}
function setup(intercept?:(r:Request,path:string)=>Response|Promise<Response>|undefined){
 const calls:{method:string;path:string;body:unknown}[]=[];
 const state={stats:{bytes:1200,files:2},jobs:[] as ReturnType<typeof job>[]};
 session.client=clientFor(async(input,init)=>{
  const request=input instanceof Request?input:new Request(String(input),init);
  const path=new URL(request.url).pathname.replace('/pleya/v1','');
  const body=request.method==='DELETE'?await request.clone().json():undefined;
  calls.push({method:request.method,path,body});
  const own=intercept?.(request,path);if(own)return own;
  if(path==='/storage/roots')return json({roots:[]});
  if(path==='/scans')return json({items:[],next_cursor:null});
  if(path==='/jobs')return json({items:state.jobs,next_cursor:null});
  if(path==='/artwork/cache'&&request.method==='GET')return json(state.stats);
  if(path==='/artwork/cache'&&request.method==='DELETE')return new Response(null,{status:202});
  return apiError('library.not_found',404);
 });
 const view=render(StoragePage);
 return {calls,state,view};
}
it('toont alleen ladderomvang en verwijdert pas na bevestiging;202 is geen leegmelding',async()=>{
 const {calls}=setup();const user=userEvent.setup();
 await screen.findByRole('heading',{name:'Verkleinde afbeeldingen'});
 expect(await screen.findByText('1,2 kB · 2 bestanden')).toBeInTheDocument();
 expect(calls.filter(c=>c.method==='DELETE')).toHaveLength(0);
 await user.click(screen.getByRole('button',{name:'Afbeeldingscache leegmaken'}));
 await user.click(within(screen.getByRole('dialog')).getByRole('button',{name:'Annuleren'}));
 expect(calls.filter(c=>c.method==='DELETE')).toHaveLength(0);
 await user.click(screen.getByRole('button',{name:'Afbeeldingscache leegmaken'}));
 await user.click(within(screen.getByRole('dialog')).getByRole('button',{name:'Leegmaken inplannen'}));
 await screen.findByText('Taak ontvangen. Volg de uitvoering bij Scans en taken.');
 expect(calls.find(c=>c.method==='DELETE')?.body).toEqual({confirm:'purge'});
 expect(screen.getByText('1,2 kB · 2 bestanden')).toBeInTheDocument();
 expect(screen.queryByText('Afbeeldingscache leeggemaakt.')).toBeNull();
 expect(screen.getByRole('link',{name:'Scans en taken'})).toHaveAttribute('href','/admin/activity');
});
it.each([false,undefined,'true'])('vraagt geen cache aan bij capability %s',async capability=>{
 session.capabilities={artwork_cache_admin:capability as boolean};
 const {calls}=setup();await screen.findByText('Wat de server hier beheert');
 expect(calls.some(c=>c.path==='/artwork/cache')).toBe(false);
 expect(screen.queryByRole('button',{name:'Afbeeldingscache leegmaken'})).toBeNull();
});
it('isoleert cacheleesfout en herprobeert zonder de roots te vervangen',async()=>{
 let fail=true;const {calls}=setup((r,p)=>p==='/artwork/cache'&&r.method==='GET'&&fail?apiError('server.internal',500):undefined);
 await screen.findByRole('alert');expect(screen.getByText('Wat de server hier beheert')).toBeInTheDocument();
 fail=false;await userEvent.click(screen.getByRole('button',{name:'Afbeeldingscache herladen'}));
 await screen.findByText('1,2 kB · 2 bestanden');
 expect(calls.filter(c=>c.path==='/storage/roots')).toHaveLength(1);
});
it.each(['account','capability','role','client','generation'])('negeert late202 na %s-wissel',async change=>{
 const pending=held<Response>();const {calls}=setup((r)=>r.method==='DELETE'?pending.promise:undefined);const user=userEvent.setup();
 await user.click(await screen.findByRole('button',{name:'Afbeeldingscache leegmaken'}));
 await user.click(within(screen.getByRole('dialog')).getByRole('button',{name:'Leegmaken inplannen'}));
 await waitFor(()=>expect(calls.some(c=>c.method==='DELETE')).toBe(true));
 if(change==='account')session.me={id:'other'};
 else if(change==='capability')session.capabilities={artwork_cache_admin:false};
 else if(change==='role')session.canAdminister=false;
 else if(change==='client')session.client=clientFor(async()=>json({roots:[],items:[],bytes:0,files:0}));
 else await session.client.signOut();
 await tick();pending.resolve(new Response(null,{status:202}));await tick();
 expect(screen.queryByText('Taak ontvangen. Volg de uitvoering bij Scans en taken.')).toBeNull();
});
it('ververst pas wanneer een waargenomen cachetaak werkelijk succeeded is',async()=>{
 const {state,calls}=setup();await screen.findByText('1,2 kB · 2 bestanden');
 state.jobs=[job('purge',{kind:'artwork_cache_purge',state:'running'})];
 await userEvent.click(screen.getByRole('button',{name:'Afbeeldingscache herladen'}));
 await screen.findByText('1,2 kB · 2 bestanden');
 state.stats={bytes:0,files:0};state.jobs[0]!.state='succeeded';
 // De bestaande jobsstatus is de bron; een ontvangen202 of lege timer is geen bewijs.
 await waitFor(()=>expect(screen.getByText('Afbeeldingscache leeggemaakt.')).toBeInTheDocument(),{timeout:4500});
 expect(screen.getByText('0 B · 0 bestanden')).toBeInTheDocument();
 expect(calls.filter(c=>c.path==='/artwork/cache'&&c.method==='GET').length).toBeGreaterThan(1);
 state.stats={bytes:1200,files:1};
 await userEvent.click(screen.getByRole('button',{name:'Afbeeldingscache herladen'}));
 await screen.findByText('1,2 kB · 1 bestand');
 expect(screen.queryByText('Afbeeldingscache leeggemaakt.')).toBeNull();
});
it('gebruikt enkelvoud voor één afgeleid bestand',async()=>{
 setup((r,p)=>p==='/artwork/cache'&&r.method==='GET'?json({bytes:1200,files:1}):undefined);
 expect(await screen.findByText('1,2 kB · 1 bestand')).toBeInTheDocument();
});
