import { render, screen, within, waitFor } from '@testing-library/svelte';
import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { editorSession as session } from './testing/session.svelte';
import { editorFake } from './metadataFake';
import { json, apiError } from '../libraryFake';
import { setLocale } from '../../i18n';
vi.mock('../../stores/session.svelte', async () => ({ session: (await import('./testing/session.svelte')).editorSession }));
import userEvent from '@testing-library/user-event';
import { tick } from 'svelte';
import ArtworkEditor from './ArtworkEditor.svelte';
import type { ArtworkCandidates, ArtworkSelection } from '../../api/types';
import MetadataEditor from './MetadataEditor.svelte';

beforeEach(() => {setLocale('nl');session.canAdminister=true;session.capabilities={metadata_overrides:true,artwork_choices:true};session.me={id:'admin'};});
afterEach(() => setLocale('en'));
it('opens artwork choices within the existing editor while preserving its fields', async () => {
 const server=editorFake((_request,path)=>path.endsWith('/artwork-candidates') ? json({item_id:'i1',base_token:'a'.repeat(64),pins:{poster:null,backdrop:null},provider_state:'available',candidates:[{id:'b'.repeat(64),role:'poster',source:'tmdb',artwork_id:null,preview_ref:'/poster.png',language:'nl',available:true}]}) : undefined);
 session.client=server.client;render(MetadataEditor,{itemId:'i1'});
 await screen.findByDisplayValue('Source summary');
 expect(await screen.findByRole('region',{name:'Afbeeldingen'})).toBeInTheDocument();
 expect(screen.getByRole('textbox',{name:'Titel'})).toBeInTheDocument();
 expect(within(screen.getByRole('navigation',{name:'Metadatavelden'})).getByRole('link',{name:'Match corrigeren'})).toHaveAttribute('href','/admin/metadata/match?item=i1');
});

const poster='b'.repeat(64),backdrop='c'.repeat(64);
function fixture(id='i1'):ArtworkCandidates{return {item_id:id,base_token:'a'.repeat(64),pins:{poster:null,backdrop:null},provider_state:'available',candidates:[{id:poster,role:'poster',source:'tmdb',artwork_id:null,preview_ref:'/poster.png',language:'nl',available:true},{id:backdrop,role:'backdrop',source:'local',artwork_id:'local-backdrop',preview_ref:null,language:null,available:true}]};}
function result(id='i1'):ArtworkSelection{return {item_id:id,base_token:'d'.repeat(64),pins:{poster:{artwork_id:'new-pin',source:'tmdb',state:'ready',error_code:null},backdrop:null}};}
function held<T>(){let resolve!:(value:T)=>void;const promise=new Promise<T>(r=>resolve=r);return {promise,resolve};}
function setup(options:{data?:ArtworkCandidates;intercept?:(request:Request,path:string)=>Response|Promise<Response>|undefined}={}){
 const server=editorFake((request,path)=>{
  const response=options.intercept?.(request,path);if(response)return response;
  if(path.endsWith('/artwork-candidates'))return json(options.data??fixture(path.split('/')[2]));
  if(path.endsWith('/artwork')&&request.method==='PUT')return json(result());
  if(path.includes('/metadata/artwork'))return new Response(new Uint8Array([1]),{headers:{'Content-Type':'image/png'}});
  return undefined;
 });session.client=server.client;const view=render(ArtworkEditor,{itemId:'i1'});return {server,view};
}
it('submits both roles atomically, retains pending choices until confirmation, then uses returned pin IDs',async()=>{
 const pending=held<Response>();const {server}=setup({intercept:request=>request.method==='PUT'?pending.promise:undefined});const user=userEvent.setup();
 await user.click(await screen.findByRole('radio',{name:/Voorbeeld poster 1/}));await user.click(screen.getByRole('radio',{name:/Voorbeeld achtergrond 1/}));
 expect(server.writes()).toHaveLength(0);expect(screen.getAllByText('Voorbeeld geselecteerd; nog niet vastgezet.')).toHaveLength(2);
 await user.click(screen.getByRole('button',{name:'Gekozen afbeeldingen vastzetten'}));expect(server.writes()[0]?.body).toEqual({base_token:'a'.repeat(64),poster,backdrop});
 expect(screen.queryByText('Afbeeldingen bevestigd en vastgezet.')).toBeNull();expect(screen.queryByText(/Vastgezet\s*·/)).toBeNull();
 const response=result();response.pins.backdrop={artwork_id:'new-wide',source:'local',state:'ready',error_code:null};pending.resolve(json(response));
 await screen.findByText('Afbeeldingen bevestigd en vastgezet.');expect(screen.getAllByText(/Vastgezet\s*·/)).toHaveLength(2);expect(screen.getByRole('button',{name:'Gekozen afbeeldingen vastzetten'})).toBeDisabled();
});
it('discard performs no write and unpin409 retains the confirmed pin with a recoverable error',async()=>{
 const data=fixture();data.pins.poster=result().pins.poster;
 const {server}=setup({data,intercept:request=>request.method==='PUT'?apiError('library.artwork_stale',409):undefined});const user=userEvent.setup();
 await user.click(await screen.findByRole('radio',{name:/Voorbeeld poster 1/}));expect(screen.getByRole('button',{name:'Losmaken: Poster'})).toBeDisabled();
 await user.click(screen.getByRole('button',{name:'Keuzes terugzetten'}));expect(server.writes()).toHaveLength(0);
 await user.click(screen.getByRole('button',{name:'Losmaken: Poster'}));expect(await screen.findByRole('alert')).toHaveTextContent('Herlaad');expect(screen.getByText(/Vastgezet\s*·/)).toBeInTheDocument();expect(screen.getByRole('button',{name:'Losmaken: Poster'})).toBeEnabled();expect(screen.queryByText(/volgt nu de bron/)).toBeNull();expect(server.writes()[0]?.body).toEqual({base_token:data.base_token,poster:null});
});
it('unpins only after server confirmation and refreshes the default item artwork',async()=>{
 const data=fixture();data.pins.poster=result().pins.poster;
 const {server}=setup({data,intercept:request=>request.method==='PUT'?json({...result(),pins:{poster:null,backdrop:null}}):undefined});const user=userEvent.setup();
 await user.click(await screen.findByRole('button',{name:'Losmaken: Poster'}));await screen.findByText(/Poster volgt nu de bron/);expect(screen.queryByRole('button',{name:'Losmaken: Poster'})).toBeNull();expect(server.calls.some(call=>call.path==='/items/i1')).toBe(true);
});
it.each(['account','item','role','capability','client','generation'])('ignores held write confirmation after %s changes',async change=>{
 const pending=held<Response>();const {server,view}=setup({intercept:request=>request.method==='PUT'?pending.promise:undefined});const user=userEvent.setup();
 await user.click(await screen.findByRole('radio',{name:/Voorbeeld poster 1/}));await user.click(screen.getByRole('button',{name:'Gekozen afbeeldingen vastzetten'}));
 if(change==='account')session.me={id:'other'};else if(change==='item')await view.rerender({itemId:'i2'});else if(change==='role')session.canAdminister=false;else if(change==='capability')session.capabilities={artwork_choices:false};else if(change==='client')session.client=editorFake(()=>json(fixture())).client;else await server.client.signOut();
 await tick();pending.resolve(json(result()));await tick();await new Promise(r=>setTimeout(r,10));expect(screen.queryByText('Afbeeldingen bevestigd en vastgezet.')).toBeNull();
});
it('rejects a mismatched read identity and permits a retry after rate limiting',async()=>{
 let count=0;setup({intercept:(_request,path)=>path.endsWith('/artwork-candidates')?(++count===1?apiError('metadata.rate_limited',429):json(fixture('wrong'))):undefined});const user=userEvent.setup();
 expect(await screen.findByRole('alert')).toHaveTextContent('Wacht even');await user.click(screen.getByRole('button',{name:'Afbeeldingskeuzes herladen'}));await waitFor(()=>expect(screen.getByRole('alert')).not.toHaveTextContent('Wacht even'));expect(screen.queryByRole('radio')).toBeNull();
});
it.each(['role','capability'])('does not request artwork without %s access',async change=>{
 if(change==='role')session.canAdminister=false;else session.capabilities={artwork_choices:false};const {server}=setup();await tick();expect(server.calls).toHaveLength(0);expect(screen.queryByRole('region',{name:'Afbeeldingen'})).toBeNull();
});
it('keeps local choices available without a provider and disables unknown or unavailable choices',async()=>{
 const data=fixture();data.provider_state='not_configured';data.candidates[0]!.source='unknown';data.candidates.push({...data.candidates[1]!,id:'e'.repeat(64),available:false});setup({data});
 expect(await screen.findByRole('radio',{name:/Voorbeeld poster 1/})).toBeDisabled();expect(screen.getByRole('radio',{name:/Voorbeeld achtergrond 1/})).toBeEnabled();expect(screen.getByRole('radio',{name:/Voorbeeld achtergrond 2/})).toBeDisabled();expect(screen.getByText(/Lokale afbeeldingen blijven/)).toBeInTheDocument();
});

it('supports artwork-only capability without requesting unavailable metadata fields',async()=>{
 session.capabilities={artwork_choices:true,metadata_overrides:false};const server=editorFake((_request,path)=>path.endsWith('/artwork-candidates')?json(fixture()):undefined);session.client=server.client;render(MetadataEditor,{itemId:'i1'});
 expect(await screen.findByRole('region',{name:'Afbeeldingen'})).toBeInTheDocument();expect(screen.queryByRole('textbox',{name:'Titel'})).toBeNull();expect(server.calls.some(call=>call.path.endsWith('/metadata'))).toBe(false);
});

it('ignores an old read after item navigation, even when transport finishes it',async()=>{
 const pending=held<Response>();const {view}=setup({intercept:(_request,path)=>path==='/items/i1/artwork-candidates'?pending.promise:undefined});await view.rerender({itemId:'i2'});await screen.findByRole('radio',{name:/Voorbeeld poster 1/});const old=fixture();old.candidates[0]!.language='old-language';pending.resolve(json(old));await tick();await new Promise(r=>setTimeout(r,10));expect(screen.queryByText(/old-language/)).toBeNull();
});
it('retains an unavailable pin, and rate-limited save keeps selection available to retry',async()=>{
 const data=fixture();data.pins.poster={...result().pins.poster!,state:'unavailable',error_code:'source_unavailable'};let writes=0;
 setup({data,intercept:request=>request.method==='PUT'?(++writes===1?apiError('metadata.rate_limited',429):json(result())):undefined});const user=userEvent.setup();
 expect(await screen.findByText('De gekozen bron is niet beschikbaar. Je keuze blijft vastgezet. Herlaad om herstel te proberen, of kies een andere afbeelding.')).toBeInTheDocument();await user.click(screen.getByRole('radio',{name:/Voorbeeld poster 1/}));await user.click(screen.getByRole('button',{name:'Gekozen afbeeldingen vastzetten'}));await waitFor(()=>expect(screen.getAllByRole('alert').some(a=>a.textContent?.includes('Wacht even'))).toBe(true));expect(screen.getByRole('radio',{name:/Voorbeeld poster 1/})).toBeChecked();await user.click(screen.getByRole('button',{name:'Gekozen afbeeldingen vastzetten'}));await screen.findByText('Afbeeldingen bevestigd en vastgezet.');
});
it('refuses a mismatched write confirmation without dropping the existing pin',async()=>{
 const data=fixture();data.pins.poster=result().pins.poster;setup({data,intercept:request=>request.method==='PUT'?json(result('wrong')):undefined});const user=userEvent.setup();await user.click(await screen.findByRole('button',{name:'Losmaken: Poster'}));expect(await screen.findByRole('alert')).toHaveTextContent('blijft behouden');expect(screen.getByRole('button',{name:'Losmaken: Poster'})).toBeEnabled();expect(screen.queryByText(/volgt nu de bron/)).toBeNull();
});

it('retries default artwork after confirmed unpin and a transient item read failure without another PUT',async()=>{
 const data=fixture();data.pins.poster=result().pins.poster;let itemReads=0;
 const {server}=setup({data,intercept:(request,path)=>request.method==='PUT'?(data.pins.poster=null,json({...result(),pins:{poster:null,backdrop:null}})):path==='/items/i1'?(++itemReads===1?apiError('internal.error',503):json({id:'i1',kind:'movie',title:'Recovered',added_at:'2026-11-02T00:00:00Z',artwork:{poster_id:'recovered-default'}})):undefined});const user=userEvent.setup();
 await user.click(await screen.findByRole('button',{name:'Losmaken: Poster'}));expect(await screen.findByRole('alert')).toHaveTextContent('De keuze is losgemaakt');expect(screen.queryByRole('button',{name:'Losmaken: Poster'})).toBeNull();
 await user.click(screen.getByRole('button',{name:'Afbeeldingskeuzes herladen'}));await waitFor(()=>expect(itemReads).toBe(2));await waitFor(()=>expect(screen.queryByRole('alert')).toBeNull());
 expect(server.writes()).toHaveLength(1);expect(server.writes()[0]?.body).toEqual({base_token:data.base_token,poster:null});expect(screen.queryByRole('button',{name:'Losmaken: Poster'})).toBeNull();
 await waitFor(()=>expect(server.calls.some(call=>call.path==='/artwork/recovered-default')).toBe(true));
});

it.each(['item','account','client','generation','role','capability'])('ignores held default retry after %s changes',async change=>{
 const data=fixture();data.pins.poster=result().pins.poster;let reads=0;const pending=held<Response>();
 const {server,view}=setup({data,intercept:(request,path)=>request.method==='PUT'?(data.pins.poster=null,json({...result(),pins:{poster:null,backdrop:null}})):path==='/items/i1'?(++reads===1?apiError('internal.error',503):pending.promise):undefined});const user=userEvent.setup();
 await user.click(await screen.findByRole('button',{name:'Losmaken: Poster'}));await screen.findByRole('alert');await user.click(screen.getByRole('button',{name:'Afbeeldingskeuzes herladen'}));await waitFor(()=>expect(reads).toBe(2));
 if(change==='item')await view.rerender({itemId:'i2'});else if(change==='account')session.me={id:'other'};else if(change==='client')session.client=editorFake(()=>json(fixture())).client;else if(change==='generation')await server.client.signOut();else if(change==='role')session.canAdminister=false;else session.capabilities={artwork_choices:false};await tick();
 pending.resolve(json({id:'i1',kind:'movie',title:'Old',added_at:'2026-11-02T00:00:00Z',artwork:{poster_id:'stale-retry'}}));await tick();await new Promise(r=>setTimeout(r,10));expect(server.calls.some(call=>call.path.includes('stale-retry'))).toBe(false);expect(server.writes()).toHaveLength(1);expect(screen.queryByText('Poster volgt nu de bron.')).toBeNull();
});
