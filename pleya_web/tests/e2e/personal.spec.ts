import {expect,test} from '@playwright/test';
import {expectNoAxeViolations,expectNoHorizontalOverflow,grid,openLibraryOfKind,signIn} from './helpers';

test.beforeEach(async({page,baseURL})=>{
  test.skip(process.env['PLEYA_E2E_PERSONAL']!=='1','personal mutations require the disposable-fixture opt-in');
  expect(new URL(baseURL!).hostname).toBe('127.0.0.1');
  await signIn(page);
});
test.afterEach(async({page})=>{
  if(!page.url().includes('/login')&&await page.getByRole('navigation').count()){
    await page.goto('/server');await page.getByRole('button',{name:'Logout',exact:true}).click();await page.waitForURL('**/login');
  }
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
