import {expect,type APIRequestContext,type Page} from '@playwright/test';
import {PASSWORD,USERNAME,expectShell,label} from './helpers';

// The personal specs write only to member accounts they create for one test and delete afterwards.
// Deleting a user cascades to its favorites, ratings and watch state (0020_personal.sql, 0007_users_sessions.sql),
// so there is nothing to restore and no other account is reached. PLEYA_E2E_SERVER_ID pins the disposable
// stack, because 127.0.0.1 can just as well be a tunnel to a real server.
export interface TemporaryAccount{id:string;username:string;password:string;headers:Record<string,string>}
export interface ItemState{favorite:boolean;rating:number|null;watched:boolean;playCount:number;hadState:boolean}

const api=(baseURL:string)=>new URL('/pleya/v1/',baseURL).toString();
async function login(request:APIRequestContext,baseURL:string,username:string,password:string):Promise<Record<string,string>>{
  const res=await request.post(`${api(baseURL)}auth/login`,{data:{username,password}});
  expect(res.ok(),`login as ${username}`).toBe(true);
  return {Authorization:`Bearer ${(await res.json()).access_token}`};
}
export async function createTemporaryAccount(request:APIRequestContext,baseURL:string):Promise<TemporaryAccount>{
  const info=await(await request.get(`${api(baseURL)}info`)).json();
  expect(info.server.id,'PLEYA_E2E_SERVER_ID must name this disposable stack').toBe(process.env['PLEYA_E2E_SERVER_ID']);
  const admin=await login(request,baseURL,USERNAME,PASSWORD);
  const username=`e2e-personal-${crypto.randomUUID().slice(0,8)}`;const password=crypto.randomUUID();
  const created=await request.post(`${api(baseURL)}users`,{headers:admin,data:{username,password,role:'member'}});
  expect(created.ok(),'create temporary account').toBe(true);
  const {id}=await created.json();
  try{
    const libraries=(await(await request.get(`${api(baseURL)}libraries`,{headers:admin})).json()).items as {id:string}[];
    const granted=await request.put(`${api(baseURL)}users/${id}/permissions`,{headers:admin,data:{permissions:libraries.map(library=>({library_id:library.id,permission:'view'}))}});
    expect(granted.ok(),'grant libraries').toBe(true);
    return {id,username,password,headers:await login(request,baseURL,username,password)};
  }catch(error){
    await request.delete(`${api(baseURL)}users/${id}`,{headers:admin});throw error;
  }
}
export async function deleteTemporaryAccount(request:APIRequestContext,baseURL:string,account:TemporaryAccount):Promise<void>{
  const admin=await login(request,baseURL,USERNAME,PASSWORD);
  const res=await request.delete(`${api(baseURL)}users/${account.id}`,{headers:admin});
  expect(res.status(),'delete temporary account').toBe(204);
}
export async function signInAs(page:Page,account:TemporaryAccount):Promise<void>{
  await page.goto('/');await page.waitForURL('**/login');
  await page.getByLabel(label('en','login.username')).fill(account.username);
  await page.getByLabel(label('en','login.password'),{exact:true}).fill(account.password);
  await page.getByRole('button',{name:label('en','login.submit')}).click();
  await expectShell(page);
}
// Any watch_states row counts, also watched=false with a play_count: no route removes one, so exact
// restoration is impossible and the suite skips such an item instead of writing to it.
export async function itemState(request:APIRequestContext,baseURL:string,account:TemporaryAccount,id:string):Promise<ItemState|null>{
  const res=await request.get(`${api(baseURL)}items/${id}`,{headers:account.headers});if(!res.ok())return null;
  const item=await res.json();const state=item.user_state;
  return {favorite:!!item.favorite,rating:item.rating??null,watched:state?.watched===true,playCount:state?.play_count??0,hadState:!!item.favorite||item.rating!=null||state!=null};
}
export async function markWatched(request:APIRequestContext,baseURL:string,account:TemporaryAccount,id:string,watched:boolean):Promise<void>{
  const res=await request.post(`${api(baseURL)}watch-state`,{headers:account.headers,data:{item_id:id,session_id:crypto.randomUUID(),position_ms:0,occurred_at:new Date().toISOString(),completed:watched,explicit_action:watched?'mark_watched':'mark_unwatched'}});
  expect(res.ok(),'watch-state').toBe(true);
}
