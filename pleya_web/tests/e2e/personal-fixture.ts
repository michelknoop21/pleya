import type {APIRequestContext} from '@playwright/test';
import {PASSWORD,USERNAME} from './helpers';

// The personal specs write favorites, ratings and watched state. They record what an item looked like
// before the test touched it and put exactly that back, so a run against an account that already has
// state never loses it. An item that already carries personal state is skipped, not overwritten.
export interface ItemBaseline{favorite:boolean;rating:number|null;watched:boolean;hadState:boolean}

const api=(baseURL:string)=>new URL('/pleya/v1/',baseURL).toString();
const sessions=new Map<string,Record<string,string>>();
async function headers(request:APIRequestContext,baseURL:string):Promise<Record<string,string>|null>{
  const known=sessions.get(baseURL);if(known)return known;
  const login=await request.post(`${api(baseURL)}auth/login`,{data:{username:USERNAME,password:PASSWORD}});
  if(!login.ok())return null;
  const fresh={Authorization:`Bearer ${(await login.json()).access_token}`};sessions.set(baseURL,fresh);return fresh;
}
export async function snapshot(request:APIRequestContext,baseURL:string,id:string):Promise<ItemBaseline|null>{
  const h=await headers(request,baseURL);if(!h)return null;
  const res=await request.get(`${api(baseURL)}items/${id}`,{headers:h});if(!res.ok())return null;
  const item=await res.json();const watched=item.user_state?.watched===true;
  // A row with watched=false and no position is what mark_unwatched leaves behind: that is not user state.
  return {favorite:!!item.favorite,rating:item.rating??null,watched,hadState:!!item.favorite||item.rating!=null||watched||(item.user_state?.position_ms??0)>0};
}
export async function restoreItem(request:APIRequestContext,baseURL:string,id:string,baseline:ItemBaseline):Promise<void>{
  const now=await snapshot(request,baseURL,id);const h=await headers(request,baseURL);if(!now||!h)return;
  const base=api(baseURL);
  if(now.favorite!==baseline.favorite){
    if(baseline.favorite)await request.put(`${base}favorites/${id}`,{headers:h});
    else await request.delete(`${base}favorites/${id}`,{headers:h});
  }
  if(now.rating!==baseline.rating){
    if(baseline.rating===null)await request.delete(`${base}ratings/${id}`,{headers:h});
    else await request.put(`${base}ratings/${id}`,{headers:h,data:{rating:baseline.rating}});
  }
  if(now.watched!==baseline.watched){
    const done=baseline.watched;
    await request.post(`${base}watch-state`,{headers:h,data:{item_id:id,session_id:crypto.randomUUID(),position_ms:0,occurred_at:new Date().toISOString(),completed:done,explicit_action:done?'mark_watched':'mark_unwatched'}});
  }
}
export async function favoriteCount(request:APIRequestContext,baseURL:string):Promise<number>{
  const h=await headers(request,baseURL);if(!h)return -1;
  const res=await request.get(`${api(baseURL)}favorites?limit=1`,{headers:h});
  return res.ok()?((await res.json()).items??[]).length:-1;
}
