// Opt-in local synthetic fixture only. Real Go HTTP/DB/scanner, no intercepted browser routes.
import {chromium,expect,request,type Page} from '@playwright/test';
import AxeBuilder from '@axe-core/playwright';
import {mkdirSync,readFileSync,writeFileSync} from 'node:fs';
const base='http://127.0.0.1:8853',out='/tmp/pleya-s11-1102';
const fixture=JSON.parse(readFileSync(`${out}/ready.json`,'utf8'));
const password='synthetic-onboarding-password';
const api=await request.newContext({baseURL:base});
const headers={'X-S11-Fixture':'synthetic-only'};
const browser=await chromium.launch({headless:true});
mkdirSync(`${out}/screens`,{recursive:true});
const frames:Record<string,unknown>[]=[],checks:Record<string,unknown>[]=[];
const errors:string[]=[],writes:string[]=[];
async function control(action:string){const r=await api.post(`/__s11/control?action=${action}`,{headers});expect(r.ok(),`fixture ${action}: ${await r.text()}`).toBe(true);return r;}
async function shot(page:Page,name:string,state:string){
 await page.evaluate(()=>window.scrollTo(0,0));await page.evaluate(()=>new Promise<void>(r=>requestAnimationFrame(()=>requestAnimationFrame(()=>r()))));
 const width=page.viewportSize()!.width;
 const geometry=await page.evaluate(()=>({viewport:innerWidth,document:document.documentElement.scrollWidth,box:document.querySelector('.setup .box')?.getBoundingClientRect().toJSON()}));
 expect(geometry.document).toBeLessThanOrEqual(width+1);if(width>=900&&geometry.box)expect(Math.round(geometry.box.width)).toBe(620);
 const file=`${name}.png`,fullFile=`${name}-full.png`;await page.screenshot({path:`${out}/screens/${file}`});await page.screenshot({path:`${out}/screens/${fullFile}`,fullPage:true});
 frames.push({screen:new URL(page.url()).pathname,state,file,fullFile,width,height:page.viewportSize()!.height,geometry});
}
async function size(page:Page,width:number,theme:string){await page.setViewportSize({width,height:width<900?844:1000});await page.evaluate(theme=>{localStorage.setItem('pleya.theme',theme);document.documentElement.dataset.theme=theme;},theme);}
async function noSecrets(page:Page){const s=await page.evaluate(()=>({l:{...localStorage},s:{...sessionStorage},cookie:document.cookie}));expect(JSON.stringify(s)).not.toContain(password);expect(JSON.stringify(s)).not.toContain(fixture.code);expect(Object.keys(s.l).some(k=>/token/i.test(k))).toBe(false);expect(Object.keys(s.s).some(k=>/token/i.test(k))).toBe(false);expect(s.cookie).not.toContain('pleya_refresh');}
const context=await browser.newContext({viewport:{width:1600,height:1000},deviceScaleFactor:1});
await context.addInitScript(()=>{localStorage.setItem('pleya.locale','nl');localStorage.setItem('pleya.theme','dark');});
const page=await context.newPage();page.on('pageerror',e=>errors.push(e.message));page.on('request',r=>{if(r.method()==='POST'&&(r.url().includes('/auth/setup')||r.url().endsWith('/libraries')||r.url().endsWith('/scan')||r.url().endsWith('/adopt')))writes.push(r.url().replace(base,''));});
try{
 await page.goto(base);await page.waitForURL('**/setup');await expect(page.getByRole('button',{name:'Eigenaar aanmaken'})).toBeVisible();
 await shot(page,'1600-dark-owner','owner before any setup mutation');await size(page,390,'light');await shot(page,'390-light-owner','owner narrow');await size(page,1600,'dark');
 await page.getByLabel('Servernaam').fill('S11 Synthetic');await page.getByLabel(/Setup/i).fill(fixture.code);await page.getByLabel('Gebruikersnaam').fill('s11owner');await page.getByLabel('Wachtwoord',{exact:true}).fill(password);await page.getByRole('button',{name:'Eigenaar aanmaken'}).click();
 await expect(page.getByRole('heading',{name:'Waar staan je bestanden?'})).toBeVisible();await noSecrets(page);await page.reload();await expect(page.getByRole('heading',{name:'Waar staan je bestanden?'})).toBeVisible();
 await shot(page,'1600-dark-storage','reload after real owner persists; storage candidates');await size(page,320,'oled');await shot(page,'320-oled-storage','available roots narrow');await size(page,1600,'dark');
 await control('fail-read');await page.getByRole('button',{name:'Status verversen'}).click();await expect(page.getByRole('alert')).toBeVisible();await shot(page,'1600-dark-read-error','real fixture HTTP503 availability failure');await control('recover-read');await page.getByRole('button',{name:'Status verversen'}).first().click();await expect(page.getByRole('alert')).toHaveCount(0);
 await page.locator(`input[type=checkbox][value="${fixture.media}"]`).check();await page.getByRole('button',{name:'Verder',exact:true}).click();await expect(page.getByLabel('Bibliotheeknaam')).toBeVisible();await page.reload();await expect(page.getByLabel('Bibliotheeknaam')).toBeVisible();
 await shot(page,'1600-dark-library','validated URL draft resumes without serverwrite');await size(page,390,'light');await shot(page,'390-light-library','first library narrow');await size(page,1600,'dark');
 await page.getByLabel('Bibliotheeknaam').fill('S11 Films');await page.getByRole('button',{name:'Bibliotheek maken'}).click();await expect(page.getByRole('button',{name:'Eerste scan starten'})).toBeVisible();await page.reload();await expect(page.getByRole('button',{name:'Eerste scan starten'})).toBeVisible();
 await shot(page,'1600-dark-scan-ready','real durable library resumes before first scan');await page.getByRole('button',{name:'Eerste scan starten'}).click();await expect(page.getByText(/Scan wacht of loopt/)).toBeVisible();await page.reload();await expect(page.getByText(/Scan wacht of loopt/)).toBeVisible();await shot(page,'1600-dark-scanning','queued/running actual scan, no second POST after reload');
 await expect(page.getByText('Scan voltooid · 1 titel')).toBeVisible({timeout:45000});await page.getByRole('button',{name:'Status verversen'}).click();await expect(page.getByText('Synthetic Journey',{exact:true})).toBeVisible();await shot(page,'1600-dark-done','real scanner found one title, existing card preview');await size(page,320,'light');await shot(page,'320-light-done','completed scan and Home action narrow');
 const axe=await new AxeBuilder({page}).include('.setup').analyze();expect(axe.violations.map(v=>v.id)).toEqual([]);checks.push({axe:'320-light',violations:0});
 await page.getByRole('link',{name:'Naar Home',exact:true}).click();await expect(page.getByRole('heading',{name:'Synthetic Journey'})).toBeVisible();await shot(page,'320-light-home','golden journey1 actual Home contains scanned title');
 expect(writes.filter(p=>p.endsWith('/auth/setup'))).toHaveLength(1);expect(writes.filter(p=>p.endsWith('/libraries'))).toHaveLength(1);expect(writes.filter(p=>p.endsWith('/scan'))).toHaveLength(1);
 const before=await (await control('counts')).json();expect(before).toMatchObject({owners:1,libraries:1,scans:1});checks.push({journey1:true,reloadBoundaries:['owner','roots-draft','library','scan'],counts:before});
 await control('adopt');await size(page,1600,'dark');await page.goto(`${base}/setup`);await expect(page.getByRole('heading',{name:'Behoud je bestaande bibliotheken'})).toBeVisible();await shot(page,'1600-dark-adopt','actual env config library offered for adoption');
 const login=await api.post('/pleya/v1/auth/login',{data:{username:'s11owner',password}});expect(login.ok()).toBe(true);const auth={Authorization:`Bearer ${(await login.json()).access_token}`};
 const beforeLibraries=await(await api.get('/pleya/v1/libraries',{headers:auth})).json();const envBefore=beforeLibraries.items.find((l:any)=>l.title==='Existing Env');expect(envBefore.managed).toBe('config');
 await page.getByRole('button',{name:'Overnemen in beheer',exact:true}).click();await page.getByRole('dialog').getByRole('button',{name:'Overnemen in beheer',exact:true}).click();await expect(page.getByRole('heading',{name:'Scan je bibliotheek'})).toBeVisible();await page.reload();await expect(page.getByRole('button',{name:'Overnemen in beheer'})).toHaveCount(0);
 const afterLibraries=await(await api.get('/pleya/v1/libraries',{headers:auth})).json();const envAfter=afterLibraries.items.find((l:any)=>l.title==='Existing Env');expect(envAfter.id).toBe(envBefore.id);expect(envAfter.managed).toBe('db');
 await page.getByRole('button',{name:'Eerste scan starten'}).click();await expect(page.getByText('Scan voltooid · 0 titels')).toBeVisible({timeout:45000});await shot(page,'1600-dark-empty','actual scanner success on empty library, no failure claim');checks.push({adoptPreservesId:true,emptyScanIsSuccess:true});
 for(const role of ['member','restricted']){
  const result=await api.post('/pleya/v1/users',{headers:auth,data:{username:`s11${role}`,password,role}});expect(result.ok()).toBe(true);
  const c=await browser.newContext({viewport:{width:390,height:844}});await c.addInitScript(()=>localStorage.setItem('pleya.locale','nl'));const p=await c.newPage();const adminReads:string[]=[];p.on('request',r=>{if(r.url().includes('/storage/roots')||r.url().includes('/scans?'))adminReads.push(r.url());});
  await p.goto(`${base}/setup`);await p.waitForURL('**/login**');await p.getByLabel('Gebruikersnaam').fill(`s11${role}`);await p.getByLabel('Wachtwoord',{exact:true}).fill(password);await p.getByRole('button',{name:'Inloggen',exact:true}).click();await p.waitForURL(url=>url.pathname==='/');await p.goto(`${base}/setup`);await expect(p.getByText('Not Found',{exact:true})).toBeVisible();expect(adminReads).toEqual([]);checks.push({role,adminReads:0});await c.close();
 }
 await noSecrets(page);expect(errors).toEqual([]);writeFileSync(`${out}/screens/manifest.json`,JSON.stringify({base,fixture:'own synthetic DB/role/container; genuine HTTP/scanner',frames,checks,writes,pageErrors:errors},null,2));console.log(JSON.stringify({PASS:true,frames:frames.length,checks}));
}finally{await context.close();await browser.close();await api.dispose();}
