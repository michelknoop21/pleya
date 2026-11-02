import type { PleyaClient } from '../../api/client';
export const setupTestSession = $state({
 phase:'ready',canAdminister:true,client:null as unknown as PleyaClient,
 me:{id:'owner',role:'owner'},capabilities:{administration:true},info:{server:{setup_accepts_name:true}},
 load:async()=>{},afterAuth:async()=>{}
});
