import {expect,it,vi} from 'vitest';
const h=vi.hoisted(()=>({phase:'ready',canAdminister:false,ensureStarted:vi.fn(async()=>{})}));
vi.mock('#lib/stores/session.svelte.js',()=>({session:h}));
import {load} from '../../routes/setup/+page';
for(const phase of ['setup','signed-out','starting','ready'])for(const admin of [true,false])it(`setupload ${phase} admin=${admin}`,async()=>{h.phase=phase;h.canAdminister=admin;if(phase==='ready'&&!admin)await expect(load()).rejects.toMatchObject({status:404});else await expect(load()).resolves.toBeUndefined();});
