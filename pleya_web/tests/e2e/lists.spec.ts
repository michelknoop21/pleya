import {expect,test,type APIRequestContext,type Page} from '@playwright/test';
import {WIDTHS,expectNoAxeViolations,expectShell,expectNoHorizontalOverflow,heightFor,label} from './helpers';
import {createTemporaryAccount,deleteTemporaryAccount,signInAs,type TemporaryAccount} from './personal-fixture';

// S19 (screens 17 and 18) against a real server, with the disposable-account opt-in of the personal specs.
let account:TemporaryAccount;
let other:TemporaryAccount|undefined;
const api=(baseURL:string)=>new URL('/pleya/v1/',baseURL).toString();
async function movies(request:APIRequestContext,baseURL:string):Promise<{id:string;title:string}[]>{
  const libraries=(await(await request.get(`${api(baseURL)}libraries`,{headers:account.headers})).json()).items as {id:string;kind:string}[];
  const library=libraries.find(entry=>entry.kind==='movies')!;
  return (await(await request.get(`${api(baseURL)}libraries/${library.id}/items`,{headers:account.headers})).json()).items;
}
async function playlistWith(request:APIRequestContext,baseURL:string,title:string,items:string[]):Promise<string>{
  const created=await(await request.post(`${api(baseURL)}playlists`,{headers:account.headers,data:{title}})).json();
  const res=await request.put(`${api(baseURL)}playlists/${created.id}/items`,{headers:account.headers,data:{item_ids:items}});
  expect(res.status(),'fill playlist').toBe(204);
  return created.id;
}
const rows=(page:Page)=>page.getByRole('main').locator('ol li');

test.beforeEach(async({page,request,baseURL})=>{
  test.skip(process.env['PLEYA_E2E_PERSONAL']!=='1','personal mutations require the disposable-fixture opt-in');
  expect(new URL(baseURL!).hostname).toBe('127.0.0.1');
  account=await createTemporaryAccount(request,baseURL!);await signInAs(page,account);
});
test.afterEach(async({request,baseURL})=>{
  if(other)await deleteTemporaryAccount(request,baseURL!,other);other=undefined;
  if(account)await deleteTemporaryAccount(request,baseURL!,account);
});

test('a playlist is made in the browser and reordered with the keyboard only',async({page,request,baseURL})=>{
  const [first,second]=await movies(request,baseURL!);expect(second,'the stack needs two films').toBeTruthy();
  const id=await playlistWith(request,baseURL!,'Sunday',[first!.id,second!.id]);
  await page.goto(`/server/playlists/${id}`);
  await expect(rows(page)).toHaveCount(2);
  await page.getByRole('button',{name:label('en','lists.reorder')}).click();
  const handle=page.getByRole('button',{name:new RegExp(`^${first!.title}, position 1`)});
  await handle.focus();await page.keyboard.press('ArrowDown');
  await expect(page.getByRole('status').filter({hasText:'position 2 of 2'})).toBeAttached();
  const save=page.getByRole('button',{name:label('en','lists.saveOrder')});
  await save.click();await expect(save).toBeHidden();
  await expect(rows(page).first()).toContainText(second!.title);
  await page.reload();
  await expect(rows(page).first()).toContainText(second!.title);
});

test('the card menu adds a title to a new playlist',async({page,request,baseURL})=>{
  const [first]=await movies(request,baseURL!);
  await page.goto('/films');
  await page.getByRole('button',{name:`Add ${first!.title} to a list`}).first().click();
  const dialog=page.getByRole('dialog');
  await dialog.getByRole('textbox',{name:label('en','lists.add.newName')}).fill('From a card');
  await dialog.getByRole('combobox',{name:label('en','lists.add.newKind')}).selectOption('playlist');
  await dialog.getByRole('button',{name:label('en','lists.add.action')}).click();
  await expect(page.getByRole('status').filter({hasText:'From a card'})).toBeVisible();
  await page.goto('/server/playlists');
  await page.getByRole('link',{name:/From a card/}).click();
  await expect(rows(page).first()).toContainText(first!.title);
});

test('a second user does not reach a playlist, and sees an honest state',async({page,request,baseURL})=>{
  const id=await playlistWith(request,baseURL!,'Mine',[]);
  other=await createTemporaryAccount(request,baseURL!);
  const res=await request.get(`${api(baseURL!)}playlists/${id}`,{headers:other.headers});
  expect(res.status()).toBe(404);
  await page.context().clearCookies();await page.evaluate(()=>{sessionStorage.clear();localStorage.clear();});
  await signInAs(page,other);
  await page.goto(`/server/playlists/${id}`);
  await expect(page.getByText(label('en','lists.notFound'))).toBeVisible();
});

test('screens 17 and 18 pass axe and have no sideways scroll on every width',async({page,request,baseURL},info)=>{
  test.skip(info.project.name!=='chromium','the spec sets every width itself');
  test.setTimeout(180_000);
  const items=(await movies(request,baseURL!)).slice(0,4).map(item=>item.id);
  const id=await playlistWith(request,baseURL!,'Sunday',items);
  const collection=await(await request.post(`${api(baseURL!)}collections`,{headers:account.headers,data:{title:'Set'}})).json();
  await request.put(`${api(baseURL!)}collections/${collection.id}/items`,{headers:account.headers,data:{item_ids:items}});
  for(const path of ['/server/playlists',`/server/playlists/${id}`,'/server/collections',`/server/collections/${collection.id}`]){
    await page.goto(path);await expectShell(page);
    await expect(page.locator('[aria-busy="true"]')).toHaveCount(0,{timeout:15_000});
    for(const width of WIDTHS){
      await page.setViewportSize({width,height:heightFor(width)});
      await expectNoAxeViolations(page,`${path} ${width}`);
      await expectNoHorizontalOverflow(page);
    }
  }
  await page.goto(`/server/playlists/${id}`);
  await page.getByRole('button',{name:label('en','lists.reorder')}).click();
  await expectNoAxeViolations(page,'reorder mode');
  await page.goto('/films');
  await page.getByRole('button',{name:/to a list$/}).first().click();
  await expect(page.getByRole('dialog')).toBeVisible();
  await expectNoAxeViolations(page,'add to list');
});
