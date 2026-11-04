import { fireEvent, render, screen, waitFor, within } from '@testing-library/svelte';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
const h = vi.hoisted(() => ({ downloads: vi.fn(), remove: vi.fn(), item: vi.fn(), libraries: vi.fn(), capabilities: { downloads: true } as Record<string, boolean> }));
vi.mock('../../../lib/stores/session.svelte.js', () => ({ session: { client: { sessionGeneration: 0, item: h.item, libraries: h.libraries }, get capabilities() { return h.capabilities; } } }));
vi.mock('../../../lib/api/personal', () => ({ personalApi: () => ({ downloads: h.downloads, deleteDownload: h.remove }) }));
import Downloads from './+page.svelte';
const download = (id: string, status = 'ready', extra = {}) => ({ id, item_id: `item-${id}`, version_id: `v-${id}`, status, size_bytes: status === 'ready' ? 4_200_000_000 : null, sha256: status === 'ready' ? 'abcdef0123456789abcdef' : null, file_url: `/f/${id}`, created_at: '2026-09-02T10:00:00Z', ...extra });
beforeEach(() => {
  h.capabilities = { downloads: true };
  h.downloads.mockReset().mockResolvedValue([]);
  h.remove.mockReset().mockResolvedValue(undefined);
  h.libraries.mockReset().mockResolvedValue([]);
  h.item.mockReset().mockImplementation(async (id: string) => ({ id, title: `Title ${id}`, kind: 'movie', versions: [{ id: id.replace('item-', 'v-'), container: 'mkv' }] }));
});
afterEach(() => vi.useRealTimers());
describe('downloads route', () => {
  it('names each download with its version, size, checksum and state', async () => {
    h.downloads.mockResolvedValueOnce([download('a')]);
    render(Downloads);
    const row = (await screen.findByRole('link', { name: 'Title item-a' })).closest('li')!;
    expect(within(row).getByText(/Original · MKV · 4.2 GB/)).toBeInTheDocument();
    expect(within(row).getByText('SHA-256 abcdef012345')).toBeInTheDocument();
    expect(within(row).getByText('ready')).toBeInTheDocument();
    expect(screen.getByText('1 of 1 files have a checksum')).toBeInTheDocument();
  });
  it('names the device, and falls back on an older download without one', async () => {
    h.downloads.mockResolvedValueOnce([download('a', 'ready', { device_name: 'Apple TV' }), download('b', 'ready', { device_name: null }), download('c')]);
    render(Downloads);
    await screen.findByRole('link', { name: 'Title item-a' });
    const meta = (name: string) => screen.getByRole('link', { name }).closest('li')!;
    expect(within(meta('Title item-a')).getByText(/· Apple TV$/)).toBeInTheDocument();
    expect(within(meta('Title item-b')).getByText(/· Device not known$/)).toBeInTheDocument();
    expect(within(meta('Title item-c')).getByText(/· Device not known$/)).toBeInTheDocument();
  });
  it('shows the own right per library', async () => {
    h.downloads.mockResolvedValueOnce([download('a')]);
    h.libraries.mockResolvedValueOnce([
      { id: 'l1', title: 'Films', kind: 'movies', item_count: 1, permission: 'view' },
      { id: 'l2', title: 'Series', kind: 'shows', item_count: 1, permission: 'download' }
    ]);
    render(Downloads);
    const films = (await screen.findByText('Films')).closest('li')!;
    expect(within(films).getByText('Watch only')).toBeInTheDocument();
    expect(within(screen.getByText('Series').closest('li')!).getByText('Can download')).toBeInTheDocument();
  });
  it('leaves the rights panel out when the server names no right or the list fails', async () => {
    h.downloads.mockResolvedValue([download('a')]);
    h.libraries.mockResolvedValueOnce([{ id: 'l1', title: 'Films', kind: 'movies', item_count: 1 }]);
    const first = render(Downloads);
    await screen.findByRole('link', { name: 'Title item-a' });
    expect(screen.queryByText('Your rights per library')).toBeNull();
    first.unmount();
    h.libraries.mockRejectedValueOnce(new Error('offline'));
    render(Downloads);
    await screen.findByRole('link', { name: 'Title item-a' });
    expect(screen.queryByText('Your rights per library')).toBeNull();
    expect(screen.queryByRole('alert')).toBeNull();
  });
  it('keeps a download whose title is no longer visible, so it can be withdrawn', async () => {
    h.downloads.mockResolvedValueOnce([download('gone')]);
    h.item.mockRejectedValueOnce(new Error('404'));
    render(Downloads);
    await screen.findByText('Title no longer available');
    expect(screen.getByRole('button', { name: 'Withdraw Title no longer available' })).toBeInTheDocument();
  });
  it('withdraws only after confirmation and removes the row', async () => {
    h.downloads.mockResolvedValueOnce([download('a'), download('b')]);
    render(Downloads);
    await fireEvent.click(await screen.findByRole('button', { name: 'Withdraw Title item-a' }));
    expect(h.remove).not.toHaveBeenCalled();
    await fireEvent.click(screen.getByRole('button', { name: 'Withdraw' }));
    expect(h.remove).toHaveBeenCalledWith('a');
    await waitFor(() => expect(screen.queryByRole('link', { name: 'Title item-a' })).toBeNull());
    expect(screen.getByRole('link', { name: 'Title item-b' })).toBeInTheDocument();
  });
  it('keeps the row and shows why when withdrawing fails', async () => {
    h.downloads.mockResolvedValueOnce([download('a')]);
    h.remove.mockRejectedValueOnce(new Error('offline'));
    render(Downloads);
    await fireEvent.click(await screen.findByRole('button', { name: 'Withdraw Title item-a' }));
    await fireEvent.click(screen.getByRole('button', { name: 'Withdraw' }));
    await screen.findByRole('alert');
    expect(screen.getByRole('link', { name: 'Title item-a' })).toBeInTheDocument();
  });
  it('polls while a download is preparing and stops when it is ready', async () => {
    vi.useFakeTimers();
    h.downloads.mockResolvedValueOnce([download('a', 'preparing')]).mockResolvedValue([download('a')]);
    render(Downloads);
    await vi.advanceTimersByTimeAsync(0);
    expect(screen.getByText('preparing')).toBeInTheDocument();
    await vi.advanceTimersByTimeAsync(5_000);
    expect(screen.getByText('ready')).toBeInTheDocument();
    await vi.advanceTimersByTimeAsync(20_000);
    expect(h.downloads).toHaveBeenCalledTimes(2);
  });
  it('offers a retry when the list fails, and nothing on an older server', async () => {
    h.downloads.mockRejectedValueOnce(new Error('offline'));
    const first = render(Downloads);
    await fireEvent.click(await screen.findByRole('button', { name: 'Retry' }));
    await screen.findByText('No downloads');
    first.unmount();
    h.capabilities = {};
    h.downloads.mockClear();
    render(Downloads);
    expect(h.downloads).not.toHaveBeenCalled();
    expect(screen.getByText('This server does not support downloads.')).toBeInTheDocument();
  });
});
