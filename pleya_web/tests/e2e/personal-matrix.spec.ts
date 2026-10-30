import {expect,test,type APIRequestContext,type Page} from '@playwright/test';
import {mkdirSync} from 'node:fs';
import {PASSWORD,expectNoAxeViolations,expectNoHorizontalOverflow,grid,label,openLibraryOfKind,signIn} from './helpers';
import {favoriteCount,restoreItem,snapshot,type ItemBaseline} from './personal-fixture';

// Opt-in like personal.spec.ts: these tests write favorites, ratings and watched state to the fixture.
// PLEYA_E2E_USER_B / PLEYA_E2E_PASS_B name a second account for the A-to-B switch.
const OUT=process.env['PLEYA_E2E_SHOTS']??'../.build/pleya-completion-evidence/windows-docker';
const USER_B=process.env['PLEYA_E2E_USER_B'];const PASS_B=process.env['PLEYA_E2E_PASS_B']??PASSWORD;
const WIDTHS=[[1920,1080],[1440,900],[1280,800],[390,844],[320,700]] as const;
const touched=new Map<string,ItemBaseline>();
test.beforeEach(async({page,baseURL})=>{
  test.skip(process.env['PLEYA_E2E_PERSONAL']!=='1','personal mutations require the disposable-fixture opt-in');
  expect(new URL(baseURL!).hostname).toBe('127.0.0.1');mkdirSync(OUT,{recursive:true});touched.clear();await signIn(page);
});
test.afterEach(async({page,request,baseURL})=>{
  await page.unrouteAll({behavior:'ignoreErrors'});
  for(const [id,baseline] of touched)await restoreItem(request,baseURL!,id,baseline);
});
async function firstMovie(page:Page,request:APIRequestContext,baseURL:string):Promise<string>{
  await openLibraryOfKind(page,'movies');await grid(page).getByRole('listitem').first().getByRole('link').click();
  await page.waitForURL(/\/items\/[^/]+$/);const id=new URL(page.url()).pathname.split('/').pop()!;
  const baseline=await snapshot(request,baseURL,id);
  test.skip(!baseline||baseline.hadState,'item already has personal state; the suite does not overwrite it');
  touched.set(id,baseline!);return id;
}
async function logout(page:Page){await page.goto('/server');await page.getByRole('button',{name:'Logout',exact:true}).click();await page.waitForURL('**/login');}

for(const [width,height] of WIDTHS){
  test(`personal surfaces at ${width}px: axe, overflow, keyboard`,async({page,request,baseURL})=>{
    await page.setViewportSize({width,height});await firstMovie(page,request,baseURL!);
    // keyboard only: focus reaches the favorite button, Enter toggles it, Space is not required
    const favorite=page.getByRole('button',{name:'Add to favorites',exact:true});
    await favorite.focus();await expect(favorite).toBeFocused();await page.keyboard.press('Enter');
    await expect(page.getByRole('button',{name:'Remove from favorites',exact:true})).toBeFocused();
    const rate=page.getByRole('button',{name:'Rate',exact:true});await rate.focus();await page.keyboard.press('Enter');
    const dialog=page.getByRole('dialog',{name:'Your rating'});await expect(dialog).toBeVisible();
    await page.getByRole('combobox',{name:'Rating',exact:true}).selectOption('8');
    await expectNoAxeViolations(page,`rating dialog ${width}`);await expectNoHorizontalOverflow(page);
    await page.screenshot({path:`${OUT}/rating-dialog@${width}.png`});
    await page.keyboard.press('Escape');await expect(dialog).toBeHidden();await expect(rate).toBeFocused();
    await page.getByRole('button',{name:'Rate',exact:true}).click();await page.getByRole('combobox',{name:'Rating',exact:true}).selectOption('8');await page.getByRole('button',{name:'Save',exact:true}).click();
    await expect(page.getByRole('button',{name:'Your rating: 8/10',exact:true})).toBeVisible();
    await expectNoAxeViolations(page,`detail ${width}`);await expectNoHorizontalOverflow(page);
    await page.screenshot({path:`${OUT}/detail@${width}.png`});
    await page.goto('/server/favorites');await expect(page.getByRole('list',{name:'Favorites',exact:true}).getByRole('listitem')).toHaveCount(1);
    await expectNoAxeViolations(page,`favorites ${width}`);await expectNoHorizontalOverflow(page);
    await page.screenshot({path:`${OUT}/favorites@${width}.png`});
    await page.goto('/server/favorites');
  });
}
test('watched and unwatched survive a reload',async({page,request,baseURL})=>{
  await firstMovie(page,request,baseURL!);
  await page.getByRole('button',{name:'Mark watched',exact:true}).click();
  await expect(page.getByRole('button',{name:'Mark unwatched',exact:true})).toBeVisible();
  await page.reload();await expect(page.getByRole('button',{name:'Mark unwatched',exact:true})).toBeVisible();
  await page.getByRole('button',{name:'Mark unwatched',exact:true}).click();
  await expect(page.getByRole('button',{name:'Mark watched',exact:true})).toBeVisible();
  await page.reload();await expect(page.getByRole('button',{name:'Mark watched',exact:true})).toBeVisible();
});
test('an empty favorites page shows the empty state, not a load-more button',async({page,request,baseURL})=>{
  test.skip((await favoriteCount(request,baseURL!))!==0,'account already has favorites');
  await page.goto('/server/favorites');
  await expect(page.getByRole('heading',{name:'No favorites yet'})).toBeVisible();
  await expect(page.getByRole('button',{name:'Load more'})).toHaveCount(0);
});
test('account B sees nothing of account A, and A returns to its own state',async({page,request,baseURL})=>{
  test.skip(!USER_B,'needs PLEYA_E2E_USER_B');
  const id=await firstMovie(page,request,baseURL!);const url=page.url();
  await page.getByRole('button',{name:'Add to favorites',exact:true}).click();
  await expect(page.getByRole('button',{name:'Remove from favorites',exact:true})).toBeVisible();
  await logout(page);
  await page.getByLabel(label('en','login.username')).fill(USER_B!);
  await page.getByLabel(label('en','login.password'),{exact:true}).fill(PASS_B);
  await page.getByRole('button',{name:label('en','login.submit')}).click();
  await page.waitForURL(u=>!u.pathname.includes('/login'));
  await page.goto(url);
  await expect(page.getByRole('button',{name:'Add to favorites',exact:true})).toHaveAttribute('aria-pressed','false');
  await page.goto('/server/favorites');
  await expect(page.getByRole('list',{name:'Favorites',exact:true}).getByRole('listitem')).toHaveCount(0);
  await logout(page);await signIn(page);await page.goto(url);
  await expect(page.getByRole('button',{name:'Remove from favorites',exact:true})).toBeVisible();
  expect(touched.has(id)).toBe(true);
});
