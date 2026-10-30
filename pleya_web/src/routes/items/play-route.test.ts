import { render, screen } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { deps, fakeApi } from '../../lib/player/playerFake';
const h=vi.hoisted(()=>({api:null as ReturnType<typeof fakeApi>|null, version:'missing'}));
vi.mock('$app/state',()=>({page:{params:{id:'movie'},get url(){return new URL('http://client.test/items/movie/play?version='+h.version);}}}));
vi.mock('$app/navigation',()=>({goto:vi.fn()}));
vi.mock('../../lib/stores/session.svelte.js',()=>({session:{client:{item:async()=>({id:'movie',kind:'movie',title:'Movie',added_at:'2026-10-30T00:00:00Z',versions:[{id:'first',container:'mp4',duration_ms:60000,file_count:1}]})},capabilities:{playback_plan:true}}}));
vi.mock('../../lib/player/browserDeps.js',()=>({browserPlayerDeps:()=>deps(h.api!)}));
import PlayRoute from './[id]/play/+page.svelte';
beforeEach(()=>{
 h.api=fakeApi();h.version='missing';
 vi.spyOn(HTMLMediaElement.prototype,'play').mockResolvedValue();
 vi.spyOn(HTMLMediaElement.prototype,'pause').mockImplementation(()=>{});
 vi.spyOn(HTMLMediaElement.prototype,'load').mockImplementation(()=>{});
});
describe('explicit playback version intent',()=>{
 it.each(['missing',''])('does not silently play the first version when an explicit ID is unavailable: %s',async version=>{
  h.version=version;
  render(PlayRoute);
  expect(await screen.findByText('That version is no longer available.')).toBeInTheDocument();
  expect(h.api!.plan).not.toHaveBeenCalled();
  expect(document.querySelector('video')).toBeNull();
 });
});
