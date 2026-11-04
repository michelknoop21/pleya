import type { PleyaClient } from '../api/client';
import { adminApi } from '../api/admin';
import type { Library, Scan, StorageRoot } from '../api/types';
export interface SetupSnapshot { libraries: Library[]; roots: StorageRoot[]; scans: Record<string,Scan|null> }
/** Reads only. Existing database records, not a stored wizard flag, own progress. */
export async function readSetup(client:PleyaClient,signal?:AbortSignal):Promise<SetupSnapshot> {
 const api=adminApi(client);
 const [libraries,roots]=await Promise.all([client.libraries(signal),api.storageRoots(signal)]);
 const scans=await Promise.all(libraries.map(l=>api.lastScan(l.id,signal)));
 return {libraries,roots,scans:Object.fromEntries(libraries.map((l,i)=>[l.id,scans[i]??null]))};
}
export function setupStage(data:SetupSnapshot):number {
 if(data.libraries.some(l=>l.managed==='config'))return 2;
 return data.libraries.length ? 3 : 1;
}
export function availableRoots(data:SetupSnapshot):StorageRoot[] {
 return data.roots.filter(r=>r.mounted && r.libraries.length===0);
}
