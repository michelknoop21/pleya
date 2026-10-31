import {expect,test,type Browser,type Page} from '@playwright/test';
import {expectShell,label,signIn} from './helpers';
import {createTemporaryAccount,deleteTemporaryAccount,signInAs,type TemporaryAccount} from './personal-fixture';

// Golden journey 11 (L.5), the web half: Michel makes a collection and shares it with Sanne, Sanne sees it, Kids
// does not, and a playlist plays in order. Michel is the owner of the disposable stack, Sanne and Kids are members
// made for this run. The app half is test/pleya_server/pleya_journey_11_live_test.dart, against the same server;
// pleya_server/scripts/journeys/journey-11.sh runs both.
let sanne:TemporaryAccount|undefined;
let kids:TemporaryAccount|undefined;
const api=(baseURL:string)=>new URL('/pleya/v1/',baseURL).toString();
const rows=(page:Page)=>page.getByRole('main').locator('ol li');

async function asUser(browser:Browser,baseURL:string,account:TemporaryAccount):Promise<Page>{
  const page=await(await browser.newContext({baseURL})).newPage();
  await signInAs(page,account);
  return page;
}

test.beforeEach(({baseURL})=>{
  test.skip(process.env['PLEYA_E2E_PERSONAL']!=='1','journey 11 writes to the disposable stack only');
  expect(new URL(baseURL!).hostname).toBe('127.0.0.1');
});
test.afterEach(async({request,baseURL})=>{
  for(const account of [sanne,kids])if(account)await deleteTemporaryAccount(request,baseURL!,account);
  sanne=kids=undefined;
});

test('a shared collection reaches Sanne and not Kids, and her playlist plays in order',async({page,browser,request,baseURL},info)=>{
  test.skip(info.project.name!=='chromium','one browser walks the journey');
  test.setTimeout(120_000);
  await signIn(page);
  sanne=await createTemporaryAccount(request,baseURL!);
  kids=await createTemporaryAccount(request,baseURL!);
  const title=`Voor Sanne ${crypto.randomUUID().slice(0,6)}`;

  // Michel makes it in the browser and picks Sanne.
  await page.goto('/server/collections');await expectShell(page);
  await page.getByRole('button',{name:label('en','lists.newCollection')}).first().click();
  const dialog=page.getByRole('dialog');
  await dialog.getByRole('textbox',{name:label('en','lists.form.name')}).fill(title);
  await dialog.getByRole('radio',{name:label('en','lists.form.users')}).check({force:true});
  await dialog.getByRole('checkbox',{name:sanne.username}).check({force:true});
  await dialog.getByRole('button',{name:label('en','lists.form.create')}).click();
  await page.waitForURL('**/server/collections/*');
  const id=new URL(page.url()).pathname.split('/').pop()!;

  // Sanne sees it, with the title that was put in.
  const libraries=(await(await request.get(`${api(baseURL!)}libraries`,{headers:sanne.headers})).json()).items as {id:string;kind:string}[];
  const films=(await(await request.get(`${api(baseURL!)}libraries/${libraries.find(entry=>entry.kind==='movies')!.id}/items`,{headers:sanne.headers})).json()).items as {id:string;title:string}[];
  expect(films.length,'the stack needs two films').toBeGreaterThanOrEqual(2);
  const sannePage=await asUser(browser,baseURL!,sanne);
  await sannePage.goto('/server/collections');
  await expect(sannePage.getByRole('link',{name:new RegExp(title)})).toBeVisible();
  await sannePage.getByRole('link',{name:new RegExp(title)}).click();
  await sannePage.waitForURL(`**/server/collections/${id}`);
  await expect(sannePage.getByRole('button',{name:label('en','lists.more')})).toHaveCount(0);

  // Kids does not: not in the list, and the address does not exist for him.
  const kidsPage=await asUser(browser,baseURL!,kids);
  await kidsPage.goto('/server/collections');
  await expectShell(kidsPage);
  await expect(kidsPage.locator('[aria-busy="true"]')).toHaveCount(0,{timeout:15_000});
  await expect(kidsPage.getByRole('link',{name:new RegExp(title)})).toHaveCount(0);
  await kidsPage.goto(`/server/collections/${id}`);
  await expect(kidsPage.getByText(label('en','lists.notFound'))).toBeVisible();
  expect((await request.get(`${api(baseURL!)}collections/${id}`,{headers:kids.headers})).status()).toBe(404);

  // Sanne's playlist plays in the order she gave it, through the end of the first title.
  const [first,second]=films;
  const created=await(await request.post(`${api(baseURL!)}playlists`,{headers:sanne.headers,data:{title:'Op volgorde'}})).json();
  const filled=await request.put(`${api(baseURL!)}playlists/${created.id}/items`,{headers:sanne.headers,data:{item_ids:[second!.id,first!.id]}});
  expect(filled.status(),'fill playlist').toBe(204);
  await sannePage.goto(`/server/playlists/${created.id}`);
  await expect(rows(sannePage).first()).toContainText(second!.title);
  await sannePage.getByRole('link',{name:label('en','lists.playAll')}).click();
  await sannePage.waitForURL(`**/items/${second!.id}/play?playlist=${created.id}`);
  await sannePage.waitForURL(`**/items/${first!.id}/play?playlist=${created.id}`,{timeout:45_000});
  await sannePage.context().close();await kidsPage.context().close();
});
