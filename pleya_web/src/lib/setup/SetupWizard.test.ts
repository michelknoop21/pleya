import { render, screen, within, waitFor } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { beforeEach, expect, it, vi } from 'vitest';
import { clientFor, json, root, library, scan, apiError } from '../admin/libraryFake';
import type { Library, Scan } from '../api/types';
import { setLocale } from '../i18n';
import { setupTestSession as session } from './testing/session.svelte';
const h = vi.hoisted(() => ({ url:new URL('http://localhost/setup'),goto:vi.fn(async()=>{}) }));
vi.mock('#lib/stores/session.svelte.js', async () => ({ session:(await import('./testing/session.svelte')).setupTestSession }));
vi.mock('$app/navigation', () => ({ goto: h.goto }));
vi.mock('$app/state', () => ({ page: { get url(){return h.url;} } }));
import Page from '../../routes/setup/+page.svelte';
let libs:Library[];let last:Scan|null;let calls:string[];
function server(intercept:(req:Request,p:string)=>Response|Promise<Response>|undefined=()=>undefined){
 const client=clientFor(async(input,init)=>{
  const req=input instanceof Request?input:new Request(String(input),init);const p=new URL(req.url).pathname.replace('/pleya/v1','');calls.push(`${req.method} ${p}`);
  const answer=intercept(req,p);if(answer)return answer;
  if(p==='/storage/roots')return json({roots:[root('/media/films',libs[0]??null)]});
  if(p==='/libraries' && req.method==='POST'){libs=[library('new','Films')];return json(libs[0],201);}
  if(p==='/libraries')return json({items:libs});
  if(p==='/scans')return json({items:last?[last]:[]});
  if(p.endsWith('/adopt')){libs=libs.map(l=>({...l,managed:'db'}));return json(libs[0]);}
  if(p.endsWith('/scan')){last=scan(libs[0]!.id,'queued');return json(last,202);}
  return apiError('library.not_found',404);
 });session.client=client;return client;
}
beforeEach(()=>{setLocale('nl');libs=[];last=null;calls=[];h.goto.mockClear();h.url=new URL('http://localhost/setup');session.phase='ready';session.canAdminister=true;session.me={id:'owner',role:'owner'};session.info={server:{setup_accepts_name:true}};session.load=vi.fn(async()=>{});server();});
it('S11 hervat na opgeslagen eigenaar bij opslag zonder opnieuw eigenaar aanmaken',async()=>{
 render(Page);expect(await screen.findByRole('heading',{name:'Waar staan je bestanden?'})).toBeInTheDocument();expect(screen.queryByLabelText('Setupcode')).toBeNull();
});
for(const role of ['member','restricted'])it(`S11 ${role} doet geen beheeraanvraag`,async()=>{
 session.me={id:role,role};session.canAdminister=false;render(Page);expect(screen.getByText('404')).toBeInTheDocument();await new Promise(r=>setTimeout(r,0));expect(calls).toEqual([]);
});
it('S11 create en echte remount hervatten zonder tweede POST',async()=>{
 const user=userEvent.setup();const view=render(Page);await user.click(await screen.findByRole('checkbox'));await user.click(screen.getByRole('button',{name:'Verder'}));await user.type(screen.getByLabelText('Bibliotheeknaam'),'Films');await user.click(screen.getByRole('button',{name:'Bibliotheek maken'}));await screen.findByRole('button',{name:'Eerste scan starten'});view.unmount();render(Page);await screen.findByRole('button',{name:'Eerste scan starten'});expect(calls.filter(c=>c==='POST /libraries')).toHaveLength(1);
});
it('S11 URLdraft wordt bij remount alleen tegen werkelijke aangeboden roots hervat',async()=>{
 h.url=new URL('http://localhost/setup?draft=library&root=/media/films&root=/outside');render(Page);await screen.findByRole('heading',{name:'Je eerste bibliotheek'});expect(screen.getByText('/media/films')).toBeInTheDocument();expect(screen.queryByText('/outside')).toBeNull();expect(calls.some(c=>c.startsWith('POST'))).toBe(false);
});
it('S11 adopted config behoudt ID en reload herhaalt adopt niet',async()=>{
 libs=[library('original','Films',{managed:'config'})];const user=userEvent.setup();const view=render(Page);await user.click(await screen.findByRole('button',{name:'Overnemen in beheer'}));await user.click(within(screen.getByRole('dialog')).getByRole('button',{name:'Overnemen in beheer'}));await screen.findByRole('button',{name:'Eerste scan starten'});expect(libs[0]!.id).toBe('original');view.unmount();render(Page);await screen.findByRole('button',{name:'Eerste scan starten'});expect(calls.filter(c=>c.includes('/adopt'))).toEqual(['POST /libraries/original/adopt']);
});
it('S11 lopende scan en remount starten geen tweede scan',async()=>{
 libs=[library('l','Films')];const user=userEvent.setup();const view=render(Page);await user.click(await screen.findByRole('button',{name:'Eerste scan starten'}));await screen.findByText(/Scan wacht of loopt/);view.unmount();render(Page);await screen.findByText(/Scan wacht of loopt/);expect(calls.filter(c=>c.endsWith('/scan'))).toHaveLength(1);
});
it('S11 frisse scanobservatie vóór write voorkomt dubbele start uit ander tabblad',async()=>{
 libs=[library('l','Films')];const user=userEvent.setup();render(Page);await screen.findByRole('button',{name:'Eerste scan starten'});last=scan('l','running');await user.click(screen.getByRole('button',{name:'Eerste scan starten'}));await screen.findByText(/Scan wacht of loopt/);expect(calls.some(c=>c.endsWith('/scan'))).toBe(false);
});
it('S11 nul titels is voltooid, failed behoudt retry',async()=>{
 libs=[library('l','Films')];last=scan('l','done');const view=render(Page);await screen.findByText('Scan voltooid · 0 titels');expect(screen.getByText(/De scan is geslaagd zonder titels/)).toBeInTheDocument();expect(screen.queryByRole('button',{name:'Scan opnieuw proberen'})).toBeNull();view.unmount();last=scan('l','failed');render(Page);await screen.findByRole('button',{name:'Scan opnieuw proberen'});
});
it('S11 readfout herstelt zonder mutatie',async()=>{
 let fail=true;server((_r,p)=>p==='/storage/roots'&&fail?apiError('server.internal',500):undefined);const user=userEvent.setup();render(Page);await screen.findByRole('button',{name:'Status verversen'});fail=false;await user.click(screen.getByRole('button',{name:'Status verversen'}));await screen.findByRole('heading',{name:'Waar staan je bestanden?'});expect(calls.some(c=>c.startsWith('POST'))).toBe(false);
});
it('S11 laat antwoord uit eerder account kan geen oude snapshot publiceren',async()=>{
 let resolve!:(r:Response)=>void;const old=new Promise<Response>(r=>resolve=r);server((_r,p)=>p==='/storage/roots'?old:undefined);render(Page);await waitFor(()=>expect(calls).toContain('GET /storage/roots'));session.me={id:'new',role:'member'};session.canAdminister=false;resolve(json({roots:[root('/old-private',null)]}));await new Promise(r=>setTimeout(r,0));expect(screen.queryByText('/old-private')).toBeNull();expect(screen.getByText('404')).toBeInTheDocument();
});
it('S11 verloren createantwoord wordt door duurzame rij herkend zonder opnieuw maken',async()=>{
 server((req,p)=>{if(p==='/libraries'&&req.method==='POST'){libs=[library('persisted','Films')];return apiError('server.internal',500);}});
 const user=userEvent.setup();render(Page);await user.click(await screen.findByRole('checkbox'));await user.click(screen.getByRole('button',{name:'Verder'}));await user.type(screen.getByLabelText('Bibliotheeknaam'),'Films');await user.click(screen.getByRole('button',{name:'Bibliotheek maken'}));await screen.findByRole('button',{name:'Eerste scan starten'});expect(calls.filter(c=>c==='POST /libraries')).toHaveLength(1);expect(screen.queryByRole('button',{name:'Bibliotheek maken'})).toBeNull();
});
it('S11 oud createvooronderzoek schrijft niet na accountwisseling',async()=>{
 let resolve!:(r:Response)=>void;let hold=false;const answer=new Promise<Response>(r=>resolve=r);server((req,p)=>p==='/libraries'&&req.method==='GET'&&hold?answer:undefined);
 const user=userEvent.setup();render(Page);await user.click(await screen.findByRole('checkbox'));await user.click(screen.getByRole('button',{name:'Verder'}));await user.type(screen.getByLabelText('Bibliotheeknaam'),'Films');hold=true;await user.click(screen.getByRole('button',{name:'Bibliotheek maken'}));session.me={id:'new',role:'member'};session.canAdminister=false;resolve(json({items:[]}));await new Promise(r=>setTimeout(r,0));expect(calls.some(c=>c==='POST /libraries')).toBe(false);
});
for(const acceptsName of [true,false])it(`S11 servernaam alleen bij onderhandeld contract ${acceptsName}`,async()=>{
 session.phase='setup';session.canAdminister=false;session.info={server:{setup_accepts_name:acceptsName}};
 const setup=vi.fn(async(_input:Parameters<typeof session.client.setup>[0])=>{});const client=session.client;vi.spyOn(client,'setup').mockImplementation(setup);session.afterAuth=vi.fn(async()=>{});
 const user=userEvent.setup();render(Page);
 if(acceptsName)await user.type(screen.getByLabelText('Servernaam'),'Kelder');else expect(screen.queryByLabelText('Servernaam')).toBeNull();
 await user.type(screen.getByLabelText(/Setup/i),'fixture-code');await user.type(screen.getByLabelText('Gebruikersnaam'),'owner');await user.type(screen.getByLabelText('Wachtwoord',{exact:true}),'fixture-pass');await user.click(screen.getByRole('button',{name:'Eigenaar aanmaken'}));
 await waitFor(()=>expect(setup).toHaveBeenCalledOnce());const body=setup.mock.calls[0]![0];
 expect(body).toMatchObject({username:'owner',setup_code:'fixture-code',password:'fixture-pass'});expect(body).not.toHaveProperty('credential_mode');
 if(acceptsName)expect(body.server_name).toBe('Kelder');else expect(body).not.toHaveProperty('server_name');
 expect((screen.getByLabelText('Wachtwoord',{exact:true}) as HTMLInputElement).value).toBe('');
});
it('S11 toont rootdraft pas nadat de hervatURL is bewaard',async()=>{
 let resolve!:()=>void;const navigated=new Promise<void>(r=>resolve=r);h.goto.mockImplementationOnce(()=>navigated);
 const user=userEvent.setup();render(Page);await user.click(await screen.findByRole('checkbox'));await user.click(screen.getByRole('button',{name:'Verder'}));
 try{expect(screen.queryByLabelText('Bibliotheeknaam')).toBeNull();}finally{resolve();}
 await screen.findByLabelText('Bibliotheeknaam');
});
it('S11 opgeslagen scan verbergt een inmiddels ontbrekende mediaroot niet',async()=>{
 libs=[library('l','Films',{item_count:1})];last=scan('l','done');server((_r,p)=>p==='/storage/roots'?json({roots:[root('/media/films',libs[0]!,{mounted:false})]}):undefined);
 render(Page);await screen.findByText(/Een bibliotheekmap is niet bereikbaar/);expect(screen.queryByRole('heading',{name:'Je server staat'})).toBeNull();
});
