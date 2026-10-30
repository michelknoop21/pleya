import {expect,test,type APIRequestContext} from '@playwright/test';
import {PASSWORD,USERNAME,expectNoAxeViolations,expectNoHorizontalOverflow,label,signIn} from './helpers';
import {createTemporaryAccount,deleteTemporaryAccount,markWatched,signInAs,type TemporaryAccount} from './personal-fixture';

// S8.4, S20.4, S23.4 and PS-4E criterion 2: state is written the way an app writes it, then read in the browser.
let account:TemporaryAccount;
const api=(baseURL:string)=>new URL('/pleya/v1/',baseURL).toString();
async function firstMovie(request:APIRequestContext,baseURL:string):Promise<{id:string;title:string;duration:number}>{
  const libraries=(await(await request.get(`${api(baseURL!)}libraries`,{headers:account.headers})).json()).items as {id:string;kind:string}[];
  const library=libraries.find(entry=>entry.kind==='movies')!;
  const page=await(await request.get(`${api(baseURL!)}libraries/${library.id}/items`,{headers:account.headers})).json();
  const {id,title,duration_ms:duration}=page.items[0];return {id,title,duration};
}
async function reportProgress(request:APIRequestContext,baseURL:string,id:string,duration:number):Promise<void>{
  // The way an app reports: a session takes the viewing over first, then samples its position.
  const session_id=crypto.randomUUID();
  for(const [position_ms,explicit_action] of [[0,'playback_started'],[Math.floor(duration*0.4),'none']] as const){
    const res=await request.post(`${api(baseURL)}watch-state`,{headers:account.headers,data:{item_id:id,session_id,position_ms,duration_ms:duration,occurred_at:new Date().toISOString(),completed:false,explicit_action,...(explicit_action==='playback_started'?{cause:'user_started'}:{})}});
    expect(res.ok(),'watch-state').toBe(true);
  }
}
async function ownerHeaders(request:APIRequestContext,baseURL:string):Promise<Record<string,string>>{
  const res=await request.post(`${api(baseURL!)}auth/login`,{data:{username:USERNAME,password:PASSWORD}});
  return {Authorization:`Bearer ${(await res.json()).access_token}`};
}
test.beforeEach(async({page,request,baseURL})=>{
  test.skip(process.env['PLEYA_E2E_PERSONAL']!=='1','personal mutations require the disposable-fixture opt-in');
  expect(new URL(baseURL!).hostname).toBe('127.0.0.1');
  account=await createTemporaryAccount(request,baseURL!);await signInAs(page,account);
});
test.afterEach(async({request,baseURL})=>{if(account)await deleteTemporaryAccount(request,baseURL!,account);});

test('a half watched title reaches Continue Watching and the history with the right progress',async({page,request,baseURL})=>{
  const movie=await firstMovie(request,baseURL!);await reportProgress(request,baseURL!,movie.id,movie.duration);
  await page.goto('/');
  const row=page.getByRole('region',{name:label('en','home.continueWatching')}).or(page.locator('section',{hasText:label('en','home.continueWatching')})).first();
  await expect(row.getByRole('link',{name:new RegExp(movie.title)}).first()).toBeVisible();
  await expect(row.locator('.prog i').first()).toHaveAttribute('style',/width: (39\.9|40)/);
  await page.goto('/server');await page.getByRole('link',{name:'Watch history',exact:true}).click();
  const entry=page.getByRole('link',{name:new RegExp(movie.title)}).first();
  await expect(entry).toContainText('40%');
  await expectNoAxeViolations(page,'history');await expectNoHorizontalOverflow(page);
});
test('search groups results, and a miss offers the last term with hits and the catalog',async({page,request,baseURL})=>{
  const movie=await firstMovie(request,baseURL!);const term=movie.title.split(/\s+/)[0]!;
  await page.goto('/search');const field=page.locator('#search-query');await field.fill(term);
  await expect(page.getByRole('heading',{name:new RegExp(`^${label('en','search.filters.movies')} \\d+`)})).toBeVisible();
  await field.fill('zqxjvw');
  await page.getByRole('button',{name:`Did you mean “${term}”?`}).click();
  await expect(field).toHaveValue(term);
  await expect(page.getByRole('heading',{name:new RegExp(`^${label('en','search.filters.movies')} \\d+`)})).toBeVisible();
  await field.fill('zqxjvw');await page.getByRole('link',{name:'Browse all films'}).click();await page.waitForURL('**/films');
});
test('a download prepared by an app is listed with its checksum and can be withdrawn',async({page,request,baseURL})=>{
  const movie=await firstMovie(request,baseURL!);const owner=await ownerHeaders(request,baseURL!);
  const libraries=(await(await request.get(`${api(baseURL!)}libraries`,{headers:owner})).json()).items as {id:string}[];
  const granted=await request.put(`${api(baseURL!)}users/${account.id}/permissions`,{headers:owner,data:{permissions:libraries.map(library=>({library_id:library.id,permission:'download'}))}});
  expect(granted.ok(),'grant download').toBe(true);
  const created=await request.post(`${api(baseURL!)}downloads`,{headers:account.headers,data:{item_id:movie.id}});expect(created.status()).toBe(201);
  await page.goto('/server/downloads');
  const row=page.getByRole('listitem').filter({hasText:movie.title});
  await expect(row.getByText('ready',{exact:true})).toBeVisible({timeout:30_000});await expect(row.getByText(/SHA-256 [0-9a-f]{12}/)).toBeVisible();
  await expectNoAxeViolations(page,'downloads');await expectNoHorizontalOverflow(page);
  await row.getByRole('button',{name:`Withdraw ${movie.title}`}).click();await page.getByRole('button',{name:'Withdraw',exact:true}).click();
  await expect(page.getByRole('heading',{name:'No downloads'})).toBeVisible();
  const list=await(await request.get(`${api(baseURL!)}downloads`,{headers:account.headers})).json();expect(list.items).toEqual([]);
  const stillThere=await request.get(`${api(baseURL!)}items/${movie.id}`,{headers:account.headers});expect(stillThere.ok(),'media stays in the library').toBe(true);
});
test('watched by names the viewer to an owner and stays away from a member',async({page,browser,request,baseURL})=>{
  const base=baseURL!;
  const movie=await firstMovie(request,base);await markWatched(request,base,account,movie.id,true);
  await page.goto(`/items/${movie.id}`);await expect(page.getByRole('heading',{level:1})).toBeVisible();
  await expect(page.getByRole('heading',{name:'Watched by'})).toHaveCount(0);
  const owner=await browser.newPage({baseURL:base});
  await signIn(owner,'en');await owner.goto(`/items/${movie.id}`);
  await expect(owner.getByRole('heading',{name:'Watched by'})).toBeVisible();await expect(owner.getByText(account.username)).toBeVisible();
  await owner.close();
});
