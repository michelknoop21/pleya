import { render, screen, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { beforeEach, afterEach, expect, it, vi } from 'vitest';
import { tick } from 'svelte';
import { editorSession as session } from './testing/session.svelte';
import { editorFake, metadataFixture } from './metadataFake';
import { json, apiError } from '../libraryFake';
import { setLocale } from '../../i18n';
vi.mock('../../stores/session.svelte', async () => ({ session: (await import('./testing/session.svelte')).editorSession }));
import MetadataEditor from './MetadataEditor.svelte';

function held<T>() { let resolve!: (value: T) => void; const promise = new Promise<T>(r => { resolve = r; }); return { promise, resolve }; }
function setup(intercept: Parameters<typeof editorFake>[0] = () => undefined) {
  const server = editorFake(intercept); session.client = server.client;
  const view = render(MetadataEditor, { itemId: 'i1' }); return { server, view };
}
beforeEach(() => { setLocale('nl'); session.canAdminister = true; session.capabilities = { metadata_overrides: true }; session.me = { id: 'admin' }; });
afterEach(() => setLocale('en'));

it('loads source and locks, and sends only a deliberate empty field', async () => {
  const { server } = setup(); const user = userEvent.setup();
  await screen.findByDisplayValue('Source summary');
  expect(within(screen.getByRole('region', { name: 'Samenvatting' })).getByText('Bron: Lokale NFO')).toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Wijzigingen opslaan' })).toBeDisabled();
  await user.click(screen.getByRole('button', { name: 'Leegmaken: Samenvatting' }));
  expect(server.writes()).toHaveLength(0);
  await user.click(screen.getByRole('button', { name: 'Wijzigingen opslaan' }));
  await screen.findByText('Wijzigingen opgeslagen en vergrendeld.');
  expect(server.writes()[0]?.body).toEqual({ summary: '' });
  const field = screen.getByRole('region', { name: 'Samenvatting' });
  expect(within(field).getByText('Bron: Handmatig')).toBeInTheDocument();
  expect(within(field).getByRole('button', { name: 'Ontgrendelen: Samenvatting' })).toBeEnabled();
});
it('uses typed people rows and year null; discard performs no write', async () => {
  const { server } = setup(); const user = userEvent.setup(); await screen.findByDisplayValue('Source summary');
  await user.click(screen.getByRole('button', { name: 'Leegmaken: Jaar' }));
  await user.click(screen.getByRole('button', { name: 'Leegmaken: Personen' }));
  await user.click(screen.getByRole('button', { name: 'Persoon toevoegen' }));
  await user.type(screen.getByLabelText('Naam 1'), 'Director');
  await user.selectOptions(screen.getByLabelText('Rol 1'), 'director');
  await user.click(screen.getByRole('button', { name: 'Wijzigingen opslaan' })); await screen.findByText('Wijzigingen opgeslagen en vergrendeld.');
  expect(server.writes()[0]?.body).toEqual({ year: null, people: [{ name: 'Director', role: 'director' }] });
  await user.type(screen.getByRole('textbox', { name: 'Titel' }), ' edited'); await user.click(screen.getByRole('button', { name: 'Wijzigingen terugzetten' }));
  expect(server.writes()).toHaveLength(1); expect(screen.getByRole('textbox', { name: 'Titel' })).toHaveValue('First film');
});
it('keeps the lock and value on unlock409, without optimistic success', async () => {
  const { server } = setup((request) => request.method === 'DELETE' ? apiError('library.override_source_unavailable', 409) : undefined);
  server.states.i1!.fields.summary = { value: 'Manual retained', source: 'manual', locked: true };
  const user = userEvent.setup(); await screen.findByDisplayValue('Manual retained');
  await user.click(screen.getByRole('button', { name: 'Ontgrendelen: Samenvatting' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('Je waarde blijft vergrendeld');
  expect(screen.getByDisplayValue('Manual retained')).toBeInTheDocument();
  expect(screen.getByRole('button', { name: 'Ontgrendelen: Samenvatting' })).toBeEnabled();
  expect(screen.queryByText(/volgt nu de bron/)).toBeNull();
});
it('does not announce or display a save before the server confirms it', async () => {
  const pending = held<Response>(); const { server } = setup(request => request.method === 'PUT' ? pending.promise : undefined);
  const user = userEvent.setup(); await screen.findByDisplayValue('Source summary');
  await user.click(screen.getByRole('button', { name: 'Leegmaken: Samenvatting' })); await user.click(screen.getByRole('button', { name: 'Wijzigingen opslaan' }));
  expect(screen.queryByText('Wijzigingen opgeslagen en vergrendeld.')).toBeNull();
  expect(within(screen.getByRole('region', { name: 'Samenvatting' })).getByText('Bron: Lokale NFO')).toBeInTheDocument();
  const result = structuredClone(server.states.i1!); result.fields.summary = { value: '', source: 'manual', locked: true }; pending.resolve(json(result));
  await screen.findByText('Wijzigingen opgeslagen en vergrendeld.');
});
it.each(['read', 'write'])('ignores held %s responses after an item change', async kind => {
  const pending = held<Response>();
  const { view } = setup((request, path) => path === '/items/i1/metadata' && kind === 'read' ? pending.promise : request.method === 'PUT' && kind === 'write' ? pending.promise : undefined);
  if (kind === 'write') { await screen.findByDisplayValue('Source summary'); const user = userEvent.setup(); await user.click(screen.getByRole('button', { name: 'Leegmaken: Samenvatting' })); await user.click(screen.getByRole('button', { name: 'Wijzigingen opslaan' })); }
  await view.rerender({ itemId: 'i2' }); await screen.findByDisplayValue('Second summary');
  pending.resolve(json(metadataFixture('i1'))); await tick(); await new Promise(resolve => setTimeout(resolve, 10));
  expect(screen.getByDisplayValue('Second summary')).toBeInTheDocument(); expect(screen.queryByText('Wijzigingen opgeslagen en vergrendeld.')).toBeNull(); expect(screen.queryByDisplayValue('Source summary')).toBeNull();
});
it.each(['account', 'role', 'capability'])('ignores held writes after %s changes', async change => {
  const pending = held<Response>(); setup(request => request.method === 'PUT' ? pending.promise : undefined);
  const user = userEvent.setup(); await screen.findByDisplayValue('Source summary');
  await user.click(screen.getByRole('button', { name: 'Leegmaken: Samenvatting' })); await user.click(screen.getByRole('button', { name: 'Wijzigingen opslaan' }));
  if (change === 'account') session.me = { id: 'other' }; else if (change === 'role') session.canAdminister = false; else session.capabilities = { metadata_overrides: false };
  pending.resolve(json(metadataFixture())); await tick(); await new Promise(resolve => setTimeout(resolve, 10));
  expect(screen.queryByText('Wijzigingen opgeslagen en vergrendeld.')).toBeNull();
  if (change !== 'account') expect(screen.queryByLabelText('Samenvatting')).toBeNull();
});
it.each(['role', 'capability'])('sends no requests without %s access', async access => {
  if (access === 'role') session.canAdminister = false; else session.capabilities = { metadata_overrides: false };
  const { server } = setup(); await screen.findByText('Deze metadata-editor is niet beschikbaar voor je account of server.');
  expect(server.calls).toEqual([]);
});
it('rejects an invalid title locally and exposes no JSON text editor', async () => {
  const { server } = setup(); const user = userEvent.setup(); await screen.findByDisplayValue('Source summary');
  await user.clear(screen.getByRole('textbox', { name: 'Titel' })); await user.click(screen.getByRole('button', { name: 'Wijzigingen opslaan' }));
  expect(await screen.findByRole('alert')).toHaveTextContent('Gebruik een niet-lege titel'); expect(server.writes()).toEqual([]);
});

it('retries a failed initial read and rejects metadata for a different item', async () => {
  let reads = 0;
  setup((_request, path) => path.endsWith('/metadata') && ++reads === 1 ? apiError('storage.unavailable', 503) : undefined);
  const user = userEvent.setup(); await screen.findByRole('button', { name: /opnieuw/i });
  await user.click(screen.getByRole('button', { name: /opnieuw/i })); await screen.findByDisplayValue('Source summary');
});
it('does not expose a mismatched response', async () => {
  setup((_request, path) => path.endsWith('/metadata') ? json(metadataFixture('i2')) : undefined);
  await screen.findByRole('button', { name: /opnieuw/i });
  expect(screen.queryByDisplayValue('Second summary')).toBeNull(); expect(screen.queryByRole('button', { name: 'Wijzigingen opslaan' })).toBeNull();
});
it('ignores a held read after a client/account switch', async () => {
  const pending = held<Response>(); setup((_request, path) => path.endsWith('/metadata') ? pending.promise : undefined);
  const other = editorFake((_request, path) => path.endsWith('/metadata') ? json({ ...metadataFixture(), fields: { ...metadataFixture().fields, summary: { value: 'Other account summary', source: 'manual', locked: true } } }) : undefined);
  session.client = other.client; session.me = { id: 'other' };
  await screen.findByDisplayValue('Other account summary');
  pending.resolve(json(metadataFixture())); await tick(); await new Promise(resolve => setTimeout(resolve, 10));
  expect(screen.getByDisplayValue('Other account summary')).toBeInTheDocument(); expect(screen.queryByDisplayValue('Source summary')).toBeNull();
});
it('retains unsaved input after a failed write and prevents unlock while dirty', async () => {
  const { server } = setup(request => request.method === 'PUT' ? apiError('storage.unavailable', 503) : undefined);
  server.states.i1!.fields.summary.locked = true; server.states.i1!.fields.summary.source = 'manual';
  const user = userEvent.setup(); await screen.findByDisplayValue('Source summary');
  await user.type(screen.getByRole('textbox', { name: 'Titel' }), ' edited');
  expect(screen.getByRole('button', { name: 'Ontgrendelen: Samenvatting' })).toBeDisabled();
  await user.click(screen.getByRole('button', { name: 'Wijzigingen opslaan' })); await screen.findByRole('alert');
  expect(screen.getByRole('textbox', { name: 'Titel' })).toHaveValue('First film edited');
  expect(screen.queryByText('Wijzigingen opgeslagen en vergrendeld.')).toBeNull();
});

it('updates the title heading only from the confirmed saved response', async () => {
  const { server } = setup(); const user = userEvent.setup(); await screen.findByDisplayValue('Source summary');
  const input = screen.getByRole('textbox', { name: 'Titel' }); await user.clear(input); await user.type(input, 'Saved title');
  expect(screen.getByRole('heading', { level: 2 })).toHaveTextContent('First film');
  await user.click(screen.getByRole('button', { name: 'Wijzigingen opslaan' }));
  await screen.findByRole('heading', { level: 2, name: 'Saved title' }); expect(server.writes()[0]?.body).toEqual({ title: 'Saved title' });
});
