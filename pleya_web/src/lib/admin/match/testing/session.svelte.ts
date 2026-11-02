import type { PleyaClient } from '../../../api/client';
class MatchTestSession {
 client = $state.raw<PleyaClient>(null!);
 canAdminister = $state(true);
 capabilities = $state({metadata_search:true,metadata_match_status:true});
 me = $state({id:'admin'});
}
export const matchTestSession = new MatchTestSession();
