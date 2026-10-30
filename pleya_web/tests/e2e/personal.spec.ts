import {expect,test,type APIRequestContext} from '@playwright/test';
import {PASSWORD,USERNAME,expectNoAxeViolations,expectNoHorizontalOverflow,grid,openLibraryOfKind,signIn} from './helpers';

const touched=new Set<string>();
// Baseline restore: an aborted run must not leave a favorite, rating or watched flag behind in the fixture.
async function restore(request:APIRequestContext,baseURL:string,ids:Iterable<string>):Promise<void>{
  const api=new URL('/pleya/v1/',baseURL).toString();
  const login=await request.post(`${api}auth/login`,{data:{username:USERNAME,password:PASSWORD}});
  if(!login.ok())return;
  const headers={Authorization:`Bearer ${(await login.json()).access_token}`};
  for(const id of ids){
    await request.delete(`${api}favorites/${id}`,{headers});
    await request.delete(`${api}ratings/${id}`,{headers});
    await request.post(`${api}watch-state`,{headers,data:{item_id:id,session_id:crypto.randomUUID(),position_ms:0,occurred_at:new Date().toISOString(),completed:false,explicit_action:'mark_unwatched'}});
  }
}
async function openFirstMovie(page:import('@playwright/test').Page):Promise<string>{
  await openLibraryOfKind(page,'movies');await grid(page).getByRole('listitem').first().getByRole('link').click();
  await page.waitForURL(/\/items\/[^/]+$/);const id=new URL(page.url()).pathname.split('/').pop()!;touched.add(id);return id;
}
test.beforeEach(async({page,baseURL})=>{
  test.skip(process.env['PLEYA_E2E_PERSONAL']!=='1','personal mutations require the disposable-fixture opt-in');
  expect(new URL(baseURL!).hostname).toBe('127.0.0.1');
  await signIn(page);
});
test.afterEach(async({page,request,baseURL})=>{
  await page.unrouteAll({behavior:'ignoreErrors'});
  if(!page.url().includes('/login')&&await page.getByRole('navigation').count()){
    await page.goto('/server');await page.getByRole('button',{name:'Logout',exact:true}).click();await page.waitForURL('**/login');
  }
  await restore(request,baseURL!,touched);touched.clear();
});
test('detail personal actions survive refresh and are reachable from My Pleya',async({page})=>{
  await openLibraryOfKind(page,'movies');await grid(page).getByRole('listitem').first().getByRole('link').click();
  await page.getByRole('button',{name:'Add to favorites',exact:true}).click();
  await expect(page.getByRole('button',{name:'Remove from favorites',exact:true})).toBeVisible();
  await page.getByRole('button',{name:'Rate',exact:true}).click();
  await page.getByRole('combobox',{name:'Rating',exact:true}).selectOption('7');
  await page.getByRole('button',{name:'Save',exact:true}).click();
  await expect(page.getByRole('button',{name:'Your rating: 7/10',exact:true})).toBeVisible();
  await page.reload();await expect(page.getByRole('button',{name:'Remove from favorites',exact:true})).toBeVisible();
  const detail=page.url();await page.goto('/server');await page.getByRole('link',{name:'Favorites',exact:true}).click();
  await expect(page.getByRole('list',{name:'Favorites',exact:true}).getByRole('listitem')).toHaveCount(1);
  await expectNoAxeViolations(page,'favorites');await expectNoHorizontalOverflow(page);
  await page.goto(detail);await page.getByRole('button',{name:'Your rating: 7/10',exact:true}).click();
  await expectNoAxeViolations(page,'rating dialog');await expectNoHorizontalOverflow(page);
  await page.getByRole('combobox',{name:'Rating',exact:true}).selectOption('');await page.getByRole('button',{name:'Save',exact:true}).click();
  await expect(page.getByRole('button',{name:'Rate',exact:true})).toBeVisible();
  await page.getByRole('button',{name:'Remove from favorites',exact:true}).click();
  await expect(page.getByRole('button',{name:'Add to favorites',exact:true})).toBeVisible();
});
test('a failed favorite request preserves the detail state',async({page})=>{
  await openLibraryOfKind(page,'movies');await grid(page).getByRole('listitem').first().getByRole('link').click();
  await page.route('**/pleya/v1/favorites/*',route=>route.abort());
  await page.getByRole('button',{name:'Add to favorites',exact:true}).click();
  await expect(page.getByRole('alert')).toBeVisible();
  await expect(page.getByRole('button',{name:'Add to favorites',exact:true})).toHaveAttribute('aria-pressed','false');
});
test('a double click sends one favorite request and the button stays locked until the answer',async({page})=>{
  await openFirstMovie(page);let puts=0;
  await page.route('**/pleya/v1/favorites/*',async route=>{if(route.request().method()==='PUT'){puts++;await new Promise(r=>setTimeout(r,800));}await route.continue();});
  const button=page.getByRole('button',{name:'Add to favorites',exact:true});
  await button.dblclick();await expect(button).toBeDisabled();
  await expect(page.getByRole('button',{name:'Remove from favorites',exact:true})).toBeEnabled();
  expect(puts).toBe(1);
});
test('a failed rating write keeps the dialog open with the error and the old rating',async({page})=>{
  await openFirstMovie(page);
  await page.route('**/pleya/v1/ratings/*',route=>route.abort());
  await page.getByRole('button',{name:'Rate',exact:true}).click();
  await page.getByRole('combobox',{name:'Rating',exact:true}).selectOption('4');
  await page.getByRole('button',{name:'Save',exact:true}).click();
  await expect(page.getByRole('dialog').getByRole('alert')).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('button',{name:'Rate',exact:true})).toBeVisible();
});
test('logging out while a favorite is pending never shows it on the next session',async({page})=>{
  await openFirstMovie(page);
  await page.route('**/pleya/v1/favorites/*',async route=>{if(route.request().method()==='PUT'){await new Promise(r=>setTimeout(r,1000));await route.fulfill({status:204});}else await route.continue();});
  await page.getByRole('button',{name:'Add to favorites',exact:true}).click();
  await page.goto('/server');await page.getByRole('button',{name:'Logout',exact:true}).click();await page.waitForURL('**/login');
  await page.waitForTimeout(1200);
  await page.unrouteAll({behavior:'ignoreErrors'});await signIn(page);
  await page.goto('/server');await page.getByRole('link',{name:'Favorites',exact:true}).click();
  await expect(page.getByRole('list',{name:'Favorites',exact:true}).getByRole('listitem')).toHaveCount(0);
});
test('a pending request of item A does not lock or change item B after navigating',async({page})=>{
  await openFirstMovie(page);
  await page.route('**/pleya/v1/favorites/*',async route=>{if(route.request().method()==='PUT'){await new Promise(r=>setTimeout(r,1500));await route.fulfill({status:204});}else await route.continue();});
  await page.getByRole('button',{name:'Add to favorites',exact:true}).click();
  await page.goBack();await grid(page).getByRole('listitem').nth(1).getByRole('link').click();
  await page.waitForURL(/\/items\/[^/]+$/);touched.add(new URL(page.url()).pathname.split('/').pop()!);
  const button=page.getByRole('button',{name:'Add to favorites',exact:true});
  await expect(button).toBeEnabled();await page.waitForTimeout(1700);
  await expect(button).toHaveAttribute('aria-pressed','false');
});
