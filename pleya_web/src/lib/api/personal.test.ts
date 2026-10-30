import { describe, expect, it, vi } from 'vitest';
import { PleyaClient, type FetchLike } from './client';
import { TokenStore, type TokenStorage } from '../auth/tokens';
import { personalApi } from './personal';
function storage():TokenStorage {const data=new Map<string,string>();return {getItem:key=>data.get(key)??null,setItem:(key,value)=>void data.set(key,value),removeItem:key=>void data.delete(key)};}
const json=(value:unknown)=>new Response(JSON.stringify(value),{headers:{'Content-Type':'application/json'}});
function setup() {
 const requests:Request[]=[];
 const fetch=vi.fn(async(input:RequestInfo|URL)=>{
  const request=input instanceof Request?input:new Request(input);requests.push(request);
  if(request.url.endsWith('/auth/login'))return json({access_token:'test-account-B',refresh_token:'test-refresh-B',expires_in_ms:600000});
  if(request.url.includes('/favorites?'))return json({items:[],next_cursor:null});
  if(request.url.endsWith('/watch-state'))return json({position_ms:0,watched:true,play_count:1,updated_at:'2026-10-30T00:00:00Z'});
  return new Response(null,{status:204});
 });
 const tokens=new TokenStore(storage(),storage());tokens.set({access_token:'test-account-A',refresh_token:'test-refresh-A',expires_in_ms:600000});
 const client=new PleyaClient({baseUrl:'http://server.test/pleya/v1',tokens,fetch:fetch as unknown as FetchLike});
 return {client,api:personalApi(client),requests,fetch};
}
describe('personal API uses the existing authenticated public client',()=>{
 it('sets/removes favorites without a body and fetches their cursor page',async()=>{
  const {api,requests}=setup();
  await api.setFavorite('item',true);await api.setFavorite('item',false);await api.favorites({cursor:'opaque',limit:24});
  expect(requests.map(request=>[request.method,new URL(request.url).pathname])).toEqual([['PUT','/pleya/v1/favorites/item'],['DELETE','/pleya/v1/favorites/item'],['GET','/pleya/v1/favorites']]);
  expect(requests.every(request=>request.headers.get('Authorization')==='Bearer test-account-A')).toBe(true);
  expect(new URL(requests[2]!.url).searchParams.get('cursor')).toBe('opaque');
 });
 it('preserves the integer 1..10 rating scale and clears with DELETE',async()=>{
  const {api,requests}=setup();await api.setRating('item',1);await api.setRating('item',10);await api.setRating('item',null);
  expect(await requests[0]!.clone().json()).toEqual({rating:1});expect(await requests[1]!.clone().json()).toEqual({rating:10});expect(requests[2]!.method).toBe('DELETE');
 });
 it.each([0,11,2.5,NaN,Infinity])('rejects invalid rating %s before dispatch',async rating=>{
  const {api,requests}=setup();await expect(api.setRating('item',rating)).rejects.toThrow();expect(requests).toHaveLength(0);
 });
 it('marks watched/unwatched explicitly without starting playback or sending new ownership fields',async()=>{
  const {api,requests}=setup();await api.setWatched('item',true,60000);await api.setWatched('item',false,60000);
  const bodies=await Promise.all(requests.map(request=>request.clone().json()));
  expect(bodies.map(body=>body.explicit_action)).toEqual(['mark_watched','mark_unwatched']);
  expect(bodies[0]).toMatchObject({item_id:'item',position_ms:60000,duration_ms:60000,completed:true});
  expect(bodies[1]).toMatchObject({position_ms:0,completed:false});
  for(const body of bodies){expect(body).not.toHaveProperty('backlog');expect(body).not.toHaveProperty('base_revision');expect(body.session_id).toMatch(/^[a-f0-9-]{36}$/);}
 });
 it('does not dispatch an old action with a replacement account',async()=>{
  const {api,client,requests}=setup();await client.login({username:'B',password:'test-only'});requests.length=0;
  await expect(api.setFavorite('item',true)).rejects.toThrow(/account/i);
  await expect(api.setRating('item',7)).rejects.toThrow(/account/i);
  await expect(api.setWatched('item',true)).rejects.toThrow(/account/i);
  await expect(api.favorites()).rejects.toThrow(/account/i);expect(requests).toHaveLength(0);
 });
 it('rejects a failed mutation instead of reporting success',async()=>{
  const {api,fetch}=setup();fetch.mockResolvedValueOnce(new Response(JSON.stringify({error:{code:'library.access_denied',message:'denied',retryable:false}}),{status:403,headers:{'Content-Type':'application/json'}}));
  await expect(api.setFavorite('item',true)).rejects.toMatchObject({status:403});
 });
 it('does not publish a late account-A mutation result after login B',async()=>{
  const {api,client,fetch}=setup();let finish!:(response:Response)=>void;
  fetch.mockImplementationOnce(()=>new Promise<Response>(resolve=>finish=resolve));
  const action=api.setRating('item',7);const rejected=expect(action).rejects.toThrow();
  await vi.waitFor(()=>expect(fetch).toHaveBeenCalledTimes(1));
  await client.login({username:'B',password:'test-only'});finish(new Response(null,{status:204}));await rejected;
 });

});
