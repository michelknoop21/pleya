import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { beforeEach, expect, it, vi } from 'vitest';
import { clientFor, json, apiError } from '../libraryFake';
import { attention } from './matchFake';
import { matchTestSession as session } from './testing/session.svelte';
import { setLocale } from '../../i18n';
vi.mock('../../stores/session.svelte', async () => ({session:(await import('./testing/session.svelte')).matchTestSession}));
import MatchPage from './MatchPage.svelte';

const items=[attention('i1','First file','unmatched'),attention('i2','Second file','unmatched')];
const candidates=(title:string,id='91')=>json({items:[{external_id:id,title,year:2018}]});
const detail=(id:string,summary:string)=>json({external_id:id,summary,genres:[],content_rating:'',poster_ref:null,backdrop_ref:null});
const status=(state='pending',stamp='2026-11-01T10:00:00.123456Z')=>json({item_id:'i1',requested_external_ids:{tmdb:91},applied_external_ids:{tmdb:10},application_state:state,error_code:state==='failed'?'application_failed':null,updated_at:stamp});
function held<T>() {let resolve!:(value:T)=>void;const promise=new Promise<T>(r=>{resolve=r;});return {promise,resolve};}
function setup(intercept:(req:Request,path:string)=>Promise<Response>|Response|undefined=()=>undefined) {
 const calls:string[]=[];
 const client=clientFor(async(input,init)=>{
  const req=input instanceof Request?input:new Request(String(input),init);const url=new URL(req.url);const path=url.pathname.replace('/pleya/v1','');calls.push(`${req.method} ${path}${url.search}`);
  const response=intercept(req,path);if(response)return response;
  if(path==='/metadata/attention')return json({items,total:items.length});
  if(path.endsWith('/metadata-search'))return candidates('Candidate for '+path.split('/')[2]);
  if(path.endsWith('/metadata-match'))return req.method==='PUT'?json({item_id:'i1',state:'matched',external_id:'91'},202):status();
  if(path.includes('/metadata-candidates/'))return detail(path.split('/').at(-1)!,'Current summary');
  return apiError('library.not_found',404);
 });
 session.client=client;render(MatchPage);return {calls,client};
}
async function search(user:ReturnType<typeof userEvent.setup>) {await user.click(await screen.findByRole('button',{name:'Zoeken'}));}
async function choose(user:ReturnType<typeof userEvent.setup>) {await search(user);await user.click(await screen.findByRole('radio'));await screen.findByText('Current summary');await user.click(screen.getByRole('button',{name:'Gebruik deze titel'}));}
beforeEach(()=>{setLocale('nl');session.canAdminister=true;session.capabilities={metadata_search:true,metadata_match_status:true};session.me={id:'admin'};});

it('negeert late zoekantwoorden na annuleren en een nieuwere zoekactie',async()=>{
 const old=held<Response>();let n=0;setup((_,p)=>p.endsWith('/metadata-search')?(++n===1?old.promise:candidates('New result')):undefined);const user=userEvent.setup();
 await search(user);await user.click(screen.getByRole('button',{name:'Zoeken annuleren'}));await search(user);expect(await screen.findByRole('radio',{name:/New result/})).not.toBeChecked();
 old.resolve(candidates('Old result'));await new Promise(r=>setTimeout(r,0));await waitFor(()=>expect(screen.queryByRole('radio',{name:/Old result/})).toBeNull());
});
it('houdt zoeking en geselecteerde details bij hetzelfde item',async()=>{
 const old=held<Response>();setup((_,p)=>p==='/items/i1/metadata-search'?old.promise:undefined);const user=userEvent.setup();await search(user);
 await user.click(screen.getByRole('button',{name:'Second file (2021) beoordelen'}));await search(user);await screen.findByRole('radio',{name:/Candidate for i2/});old.resolve(candidates('Wrong item result'));await new Promise(r=>setTimeout(r,0));
 await waitFor(()=>expect(screen.queryByRole('radio',{name:/Wrong item/})).toBeNull());
});
it('negeert omgekeerde kandidaatdetails',async()=>{
 const old=held<Response>();setup((_,p)=>p.endsWith('/metadata-search')?json({items:[{external_id:'91',title:'One',year:2018},{external_id:'92',title:'Two',year:2019}]}):p.endsWith('/metadata-candidates/91')?old.promise:p.endsWith('/metadata-candidates/92')?detail('92','Second summary'):undefined);
 const user=userEvent.setup();await search(user);await user.click(await screen.findByRole('radio',{name:/One/}));await user.click(screen.getByRole('radio',{name:/Two/}));await screen.findByText('Second summary');old.resolve(detail('91','Old sensitive summary'));await new Promise(r=>setTimeout(r,0));
 await waitFor(()=>expect(screen.queryByText('Old sensitive summary')).toBeNull());expect(screen.getByRole('radio',{name:/Two/})).toBeChecked();
});
it('verwerpt gehouden resultaten na accountwisseling',async()=>{
 const old=held<Response>();setup((_,p)=>p.endsWith('/metadata-search')?old.promise:undefined);const user=userEvent.setup();await search(user);
 session.me={id:'other-admin'};session.client=clientFor(async()=>json({items:[],total:0}));old.resolve(candidates('Previous account'));await new Promise(r=>setTimeout(r,0));
 await waitFor(()=>expect(screen.queryByRole('radio',{name:/Previous account/})).toBeNull());expect(screen.queryByText('Current summary')).toBeNull();
});
it('intrekken stopt gevoelige details en bevestigingen',async()=>{
 const old=held<Response>();const server=setup((_,p)=>p.includes('/metadata-candidates/')?old.promise:undefined);const user=userEvent.setup();await search(user);await user.click(await screen.findByRole('radio'));
 session.canAdminister=false;old.resolve(detail('91','Revoked summary'));await new Promise(r=>setTimeout(r,0));await waitFor(()=>expect(screen.queryByRole('button',{name:'Gebruik deze titel'})).toBeNull());expect(screen.queryByText('Revoked summary')).toBeNull();expect(server.calls.some(c=>c.startsWith('PUT'))).toBe(false);
});
it('bindt de bevestiging aan het vastgelegde item en wist hem bij itemwisseling',async()=>{
 const server=setup();const user=userEvent.setup();await choose(user);expect(await screen.findByRole('dialog')).toHaveTextContent('First file');
 // Direct activation models a route/item change while the modal is open.
 screen.getByRole('button',{name:'Second file (2021) beoordelen'}).click();
 await waitFor(()=>expect(screen.queryByRole('dialog')).toBeNull());expect(server.calls.some(c=>c.startsWith('PUT'))).toBe(false);
});
it('schrijft geen succes of status van het vorige account na een gehouden PUT',async()=>{
 const old=held<Response>();const server=setup((r,p)=>r.method==='PUT'&&p.endsWith('/metadata-match')?old.promise:undefined);const user=userEvent.setup();await choose(user);await user.click(within(await screen.findByRole('dialog')).getByRole('button',{name:'Koppelen'}));
 await waitFor(()=>expect(server.calls.some(c=>c.startsWith('PUT'))).toBe(true));session.me={id:'other'};session.client=clientFor(async()=>json({items:[],total:0}));old.resolve(json({item_id:'i1',state:'matched',external_id:'91'},202));await new Promise(r=>setTimeout(r,0));
 await waitFor(()=>expect(screen.queryByText(/Keuze ontvangen/)).toBeNull());expect(screen.queryByText('Metadata toegepast')).toBeNull();
});
it('behoudt exact microseconden en nieuwste status bij omgekeerde antwoorden',async()=>{
 const old=held<Response>();let n=0;setup((_,p)=>p==='/items/i1/metadata-match'?(++n===2?old.promise:status(n>=3?'failed':'pending',n>=3?'2026-11-01T10:00:00.123457Z':'2026-11-01T10:00:00.123456Z')):undefined);
 const user=userEvent.setup();await screen.findByText('Verwerking loopt');await user.click(screen.getByRole('button',{name:'Status verversen'}));await user.click(screen.getByRole('button',{name:'Status verversen'}));await screen.findByText(/Toepassen mislukt/);
 old.resolve(status('applied','2026-11-01T10:00:00.123456Z'));await new Promise(r=>setTimeout(r,0));await waitFor(()=>expect(screen.queryByText('Metadata toegepast')).toBeNull());expect(screen.getByText(/Toepassen mislukt/).closest('section')).toHaveAttribute('data-generation','2026-11-01T10:00:00.123457Z');expect(screen.getByText('Toegepast: 10')).toBeInTheDocument();
 await user.click(screen.getByRole('button',{name:'Deze keuze opnieuw proberen'}));expect(await screen.findByRole('dialog')).toHaveTextContent('nummer 91');
});
it('annuleert alleen de statusread en behoudt eerder toegepast bewijs',async()=>{
 const old=held<Response>();let n=0;setup((_,p)=>p==='/items/i1/metadata-match'&&++n>1?old.promise:undefined);const user=userEvent.setup();await screen.findByText('Toegepast: 10');await user.click(screen.getByRole('button',{name:'Status verversen'}));await user.click(await screen.findByRole('button',{name:'Statusverzoek annuleren'}));old.resolve(status('applied'));await new Promise(r=>setTimeout(r,0));
 await waitFor(()=>expect(screen.queryByText('Metadata toegepast')).toBeNull());expect(screen.getByText('Toegepast: 10')).toBeInTheDocument();
});
it('oude capabilities houden handmatige ID en reject zonder nieuwe endpointcalls',async()=>{
 session.capabilities={metadata_search:false,metadata_match_status:false};const server=setup();const user=userEvent.setup();await screen.findByLabelText('Nummer bij de provider');expect(screen.queryByRole('button',{name:'Zoeken'})).toBeNull();
 await user.type(screen.getByLabelText('Nummer bij de provider'),'91');await user.click(screen.getByRole('button',{name:'Dit nummer gebruiken'}));await user.click(within(await screen.findByRole('dialog')).getByRole('button',{name:'Annuleren'}));
 await user.click(screen.getByRole('button',{name:'Match afwijzen'}));expect(await screen.findByRole('dialog')).toBeInTheDocument();expect(server.calls.every(c=>c.includes('/metadata/attention'))).toBe(true);
});
it('bindt ook de afwijsbevestiging aan het oorspronkelijke account vóór een renderflush',async()=>{
 const server=setup();const user=userEvent.setup();await screen.findByRole('button',{name:'Zoeken'});await user.click(screen.getByText('Geavanceerd'));await user.click(screen.getByRole('button',{name:'Match afwijzen'}));
 const confirm=within(await screen.findByRole('dialog')).getByRole('button',{name:'Afwijzen'});
 session.me={id:'other-admin'};
 confirm.click();
 await new Promise(resolve=>setTimeout(resolve,20));
 expect(server.calls.some(c=>c.startsWith('DELETE'))).toBe(false);
});
for(const [code,http,message] of [
 ['library.metadata_failed',502,'De provider kon dit verzoek niet afronden'],
 ['library.metadata_unavailable',503,'De provider is niet beschikbaar'],
 ['auth.rate_limited',429,'Te veel verzoeken']
] as const) it(`veilige zoekfout ${http} houdt retry en handmatige uitweg bereikbaar`,async()=>{
 setup((_,p)=>p.endsWith('/metadata-search')?apiError(code,http):undefined);const user=userEvent.setup();await search(user);expect(await screen.findByRole('alert')).toHaveTextContent(message);expect(screen.getByRole('button',{name:'Opnieuw proberen'})).toBeEnabled();await user.click(screen.getByText('Geavanceerd'));expect(screen.getByLabelText('Nummer bij de provider')).toBeVisible();expect(screen.queryByRole('radio')).toBeNull();
});
it('de statusfout claimt geen toepassing en houdt expliciet verversen bereikbaar',async()=>{
 setup((_,p)=>p.endsWith('/metadata-match')?apiError('server.internal',500):undefined);expect(await screen.findByRole('alert')).toHaveTextContent('Status kon niet worden gelezen');expect(screen.queryByText('Metadata toegepast')).toBeNull();expect(screen.getByRole('button',{name:'Status verversen'})).toBeEnabled();
});
it('een detailsfout houdt de kandidaat en handmatige uitweg zonder toepasknop vrij te geven',async()=>{
 setup((_,p)=>p.includes('/metadata-candidates/')?apiError('library.metadata_failed',502):undefined);const user=userEvent.setup();await search(user);await user.click(await screen.findByRole('radio'));expect(await screen.findByRole('alert')).toHaveTextContent('De provider kon dit verzoek niet afronden');expect(screen.getByRole('button',{name:'Gebruik deze titel'})).toBeDisabled();await user.click(screen.getByText('Geavanceerd'));expect(screen.getByLabelText('Nummer bij de provider')).toBeVisible();
});
it('een ontvangen nieuwe keuze heft ook de zichtbare oude afwijzing op',async()=>{
 let received=false;
 setup((req,p)=>p==='/metadata/attention'?json({items:received?[]:[{...items[0],state:'rejected'}],total:received?0:1}):req.method==='PUT'&&p.endsWith('/metadata-match')?(received=true,json({item_id:'i1',state:'matched',external_id:'91'},202)):undefined);
 const user=userEvent.setup();await screen.findByText(/Deze titel is al afgewezen/);await choose(user);await user.click(within(await screen.findByRole('dialog')).getByRole('button',{name:'Koppelen'}));await screen.findByText(/Keuze ontvangen/);
 await waitFor(()=>expect(screen.queryByText(/Deze titel is al afgewezen/)).toBeNull());
 expect(screen.queryByText('Metadata toegepast')).toBeNull();
 await user.click(screen.getByText('Geavanceerd'));expect(screen.getByRole('button',{name:'Match afwijzen'})).toBeEnabled();
});

// R0/I1: receipt is temporary uncertainty, not a durable application outcome.
function receiptStatus(state:string,stamp:string|null,requested=91,applied=state==='applied'?91:10) {
 return json({item_id:'i1',requested_external_ids:{tmdb:requested},applied_external_ids:{tmdb:applied},application_state:state,error_code:state==='failed'?'application_failed':null,updated_at:stamp});
}
async function confirmChoice(user:ReturnType<typeof userEvent.setup>) {
 await user.click(within(await screen.findByRole('dialog')).getByRole('button',{name:'Koppelen'}));
 await screen.findByText(/Keuze ontvangen/);
}
for(const [terminal,before,after] of [['applied','2026-11-01T10:00:00.123456Z','2026-11-01T10:00:00.123457Z'],['failed','2026-11-01T10:00:00.123456Z','2026-11-01T10:00:00.123457Z'],['applied','2026-11-01T10:00:00Z','2026-11-01T10:00:00.000001Z']] as const) it(`R0 ontvangst verdwijnt na bewezen ${terminal} ${before} → ${after}`,async()=>{
 let received=false;let state='pending';
 setup((req,p)=>p==='/items/i1/metadata-match'?(req.method==='PUT'?(received=true,json({item_id:'i1',state:'matched',external_id:'91'},202)):receiptStatus(state,received?after!:before!)):undefined);
 const user=userEvent.setup();await choose(user);await confirmChoice(user);expect(screen.getByText(/nog niet bevestigd als toegepast/)).toBeInTheDocument();
 state=terminal;await user.click(screen.getByRole('button',{name:'Status verversen'}));await screen.findByText(terminal==='applied'?'Metadata toegepast':/Toepassen mislukt/);
 await waitFor(()=>expect(screen.queryByText(/nog niet bevestigd als toegepast/)).toBeNull());
 if(terminal==='failed')expect(screen.getByText('Toegepast: 10')).toBeInTheDocument();
});
for(const outcome of ['legacy','unknown','failure']) it(`R0 ${outcome} houdt ontvangen keuze eerlijk onbevestigd`,async()=>{
 let received=false;if(outcome==='legacy')session.capabilities={metadata_search:true,metadata_match_status:false};
 const server=setup((req,p)=>p==='/items/i1/metadata-match'?(req.method==='PUT'?(received=true,json({item_id:'i1',state:'matched',external_id:'91'},202)):received&&outcome==='failure'?apiError('server.internal',500):receiptStatus('unknown',null)):undefined);
 const user=userEvent.setup();await choose(user);await confirmChoice(user);
 if(outcome==='unknown')await screen.findByText('Toepassingsstatus onbekend');if(outcome==='failure')await screen.findByText(/Status kon niet worden gelezen/);
 expect(screen.getByText(/nog niet bevestigd als toegepast/)).toBeInTheDocument();expect(screen.queryByText('Metadata toegepast')).toBeNull();
 if(outcome==='legacy')expect(server.calls.filter(c=>c==='GET /items/i1/metadata-match')).toHaveLength(0);
});
it('R0 oudere microgeneratie of ander request wist geen nieuwe ontvangst; previewkeuze is geen request',async()=>{
 let received=false;let state='pending';let stamp='2026-11-01T10:00:00.123457Z';let requested=91;
 setup((req,p)=>p==='/items/i1/metadata-match'?(req.method==='PUT'?(received=true,json({item_id:'i1',state:'matched',external_id:'91'},202)):receiptStatus(state,stamp,requested,91)):p.endsWith('/metadata-search')?json({items:[{external_id:'91',title:'One',year:2018},{external_id:'92',title:'Two',year:2019}]}):undefined);
 const user=userEvent.setup();await search(user);await user.click(await screen.findByRole('radio',{name:/One/}));await screen.findByText('Current summary');await user.click(screen.getByRole('button',{name:'Gebruik deze titel'}));await confirmChoice(user);
 state='applied';stamp='2026-11-01T10:00:00.123456999Z';await user.click(screen.getByRole('button',{name:'Status verversen'}));await screen.findByText('Metadata toegepast');expect(screen.getByText(/nog niet bevestigd als toegepast/)).toBeInTheDocument();
 stamp='2026-11-01T10:00:00.123457001Z';requested=92;await user.click(screen.getByRole('button',{name:'Status verversen'}));await new Promise(r=>setTimeout(r,0));expect(screen.getByText(/nog niet bevestigd als toegepast/)).toBeInTheDocument();
 // A different read-only preview must not change which received ID is being observed.
 await user.click(screen.getByRole('radio',{name:/Two/}));await screen.findByText('Current summary');requested=91;await user.click(screen.getByRole('button',{name:'Status verversen'}));await waitFor(()=>expect(screen.queryByText(/nog niet bevestigd als toegepast/)).toBeNull());expect(received).toBe(true);
});
it('R0 een gehouden oudere status kan de nieuwere ontvangst niet afronden',async()=>{
 const old=held<Response>();let holdNext=false;let puts=0;
 setup((req,p)=>p==='/items/i1/metadata-match'?(req.method==='PUT'?(puts++,json({item_id:'i1',state:'matched',external_id:'91'},202)):holdNext?(holdNext=false,old.promise):receiptStatus('pending',puts>1?'2026-11-01T10:00:00.123459Z':'2026-11-01T10:00:00.123457Z')):undefined);
 const user=userEvent.setup();await choose(user);await confirmChoice(user);await screen.findByText('Verwerking loopt');holdNext=true;await user.click(screen.getByRole('button',{name:'Status verversen'}));await user.click(screen.getByRole('button',{name:'Gebruik deze titel'}));await confirmChoice(user);await waitFor(()=>expect(puts).toBe(2));
 old.resolve(receiptStatus('applied','2026-11-01T10:00:00.123458Z'));await new Promise(r=>setTimeout(r,0));expect(screen.getByText(/nog niet bevestigd als toegepast/)).toBeInTheDocument();expect(screen.queryByText('Metadata toegepast')).toBeNull();
});
it('R0 terminale status wist geen afwijzingsmelding van een andere actie',async()=>{
 setup((req,p)=>p==='/items/i1/metadata-match'?(req.method==='DELETE'?json({item_id:'i1',state:'rejected',external_id:null}):req.method==='GET'?receiptStatus('applied','2026-11-01T10:00:00.123459Z'):undefined):undefined);
 const user=userEvent.setup();await screen.findByRole('button',{name:'Zoeken'});await user.click(screen.getByText('Geavanceerd'));await user.click(screen.getByRole('button',{name:'Match afwijzen'}));await user.click(within(await screen.findByRole('dialog')).getByRole('button',{name:'Afwijzen'}));await screen.findByText(/is afgewezen/);await user.click(screen.getByRole('button',{name:'Status verversen'}));await new Promise(r=>setTimeout(r,0));expect(screen.getByText(/is afgewezen/)).toBeInTheDocument();
});
