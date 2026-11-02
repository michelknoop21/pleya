import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { clientFor, json } from '../libraryFake';
import { attention } from './matchFake';
import { setLocale } from '../../i18n';
const h = vi.hoisted(() => ({ client: null as unknown, canAdminister: true }));
vi.mock('../../stores/session.svelte', () => ({ session: {
 get client() { return h.client; }, get canAdminister() { return h.canAdminister; },
 capabilities: { metadata_search: true, metadata_match_status: true }, me: { id: 'admin' }
} }));
import MatchPage from './MatchPage.svelte';

function setup() {
 const calls: string[] = []; let applied = false; let requested = false;
 const item = attention('i1', 'De laatste overtocht', 'unmatched', {year: 2018});
 h.client = clientFor(async (input, init) => {
  const req = input instanceof Request ? input : new Request(String(input), init);
  const u = new URL(req.url); const path = u.pathname.replace('/pleya/v1', '');
  calls.push(`${req.method} ${path}${u.search}`);
  if (path === '/metadata/attention') return json({ items: requested ? [] : [item], total: requested ? 0 : 1 });
  if (path.endsWith('/metadata-search')) return json({items: [{external_id:'91',title:'De laatste overtocht',year:2018,original_title:'The Last Crossing'}]});
  if (path.endsWith('/metadata-candidates/91')) return json({external_id:'91',summary:'A real selected summary',genres:['Drama'],content_rating:'12',poster_ref:null,backdrop_ref:null});
  if (path.endsWith('/metadata-match')) {
   if (req.method === 'PUT') { requested=true; return json({item_id:'i1',state:'matched',external_id:'91'},202); }
   return json({item_id:'i1',requested_external_ids:requested ? {tmdb:91} : null,applied_external_ids:applied ? {tmdb:91} : {tmdb:10},application_state: applied ? 'applied' : requested ? 'pending' : 'unknown',error_code:null,updated_at:requested ? '2026-11-01T10:00:00.123457Z':'2026-11-01T10:00:00.123456Z'});
  }
  return json({error:{code:'library.not_found',message:'missing',retryable:false}},404);
 });
 render(MatchPage);
 return { calls, apply: () => {applied = true;} };
}
beforeEach(() => {setLocale('nl'); h.canAdminister=true;});
describe('echte zoekcaller en status', () => {
 it('zoekt, leest uitsluitend geselecteerde details en houdt 202 pending naast applied A', async () => {
  const server=setup(); const user=userEvent.setup();
  await user.click(await screen.findByRole('button',{name:'Zoeken'}));
  const card=await screen.findByRole('radio',{name:/De laatste overtocht.*2018/});
  expect(card).not.toBeChecked();
  expect(server.calls.some(c=>c.includes('/metadata-candidates/'))).toBe(false);
  await user.click(card);
  expect(await screen.findByText('A real selected summary')).toBeInTheDocument();
  await user.click(screen.getByRole('button',{name:'Gebruik deze titel'}));
  expect(server.calls.some(c=>c.startsWith('PUT'))).toBe(false);
  await user.click(within(await screen.findByRole('dialog')).getByRole('button',{name:'Koppelen'}));
  expect(await screen.findByText(/Keuze ontvangen/)).toBeInTheDocument();
  expect(await screen.findByText(/Verwerking loopt/)).toBeInTheDocument();
  expect(screen.getByText(/Toegepast: 10/)).toBeInTheDocument();
  expect(screen.getByRole('button',{name:'Gebruik deze titel'})).toBeInTheDocument();
  server.apply();
  await user.click(screen.getByRole('button',{name:'Status verversen'}));
  expect(await screen.findByText('Metadata toegepast')).toBeInTheDocument();
  await waitFor(()=>expect(server.calls.filter(c=>c.startsWith('PUT'))).toHaveLength(1));
 });
});
