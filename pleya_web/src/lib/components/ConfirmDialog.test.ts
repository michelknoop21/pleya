import { afterEach, describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';
import { tick } from 'svelte';

import ConfirmDialog from './ConfirmDialog.svelte';

const base = {
  title: 'Delete library Films?',
  message: 'This removes 461 titles from the catalogue.',
  confirmLabel: 'Delete'
};

const openers: HTMLButtonElement[] = [];

/** Een knop buiten de dialoog die de focus heeft voor die opent. */
function trigger(): HTMLButtonElement {
  const button = document.createElement('button');
  openers.push(button);
  button.textContent = 'Open';
  document.body.append(button);
  button.focus();
  return button;
}

async function settle(): Promise<void> {
  await tick();
  await tick();
}

afterEach(() => {
  openers.splice(0).forEach((b) => b.remove());
});

describe('ConfirmDialog', () => {
  it('rendert niets zolang hij dicht is', () => {
    render(ConfirmDialog, { props: { ...base, onconfirm: vi.fn() } });
    expect(screen.queryByRole('dialog')).toBeNull();
  });

  it('is een modale dialoog, benoemd door de titel en beschreven door de tekst', () => {
    render(ConfirmDialog, { props: { ...base, open: true, onconfirm: vi.fn() } });
    const dialog = screen.getByRole('dialog', { name: 'Delete library Films?' });
    expect(dialog).toHaveAttribute('aria-modal', 'true');
    expect(dialog).toHaveAccessibleDescription('This removes 461 titles from the catalogue.');
  });

  it('zet de focus op de veilige knop zonder veld en geeft hem bij sluiten terug', async () => {
    const opener = trigger();
    const { rerender } = render(ConfirmDialog, {
      props: { ...base, open: true, onconfirm: vi.fn() }
    });
    await settle();
    expect(screen.getByRole('button', { name: 'Cancel' })).toHaveFocus();

    await rerender({ open: false });
    await settle();
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(opener).toHaveFocus();
  });

  it('sluit op Escape, meldt de annulering en zet de focus terug', async () => {
    const opener = trigger();
    const oncancel = vi.fn();
    const onconfirm = vi.fn();
    render(ConfirmDialog, { props: { ...base, open: true, onconfirm, oncancel } });
    await settle();

    await userEvent.keyboard('{Escape}');
    await settle();
    expect(oncancel).toHaveBeenCalledOnce();
    expect(onconfirm).not.toHaveBeenCalled();
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(opener).toHaveFocus();
  });

  it('houdt Tab binnen de dialoog', async () => {
    trigger();
    render(ConfirmDialog, { props: { ...base, open: true, danger: false, onconfirm: vi.fn() } });
    await settle();
    const cancel = screen.getByRole('button', { name: 'Cancel' });
    const confirm = screen.getByRole('button', { name: 'Delete' });
    expect(cancel).toHaveFocus();

    await userEvent.tab();
    expect(confirm).toHaveFocus();
    await userEvent.tab();
    expect(cancel).toHaveFocus();
    await userEvent.tab({ shift: true });
    expect(confirm).toHaveFocus();
  });

  it('houdt bevestigen dicht tot de zin exact overgetypt is', async () => {
    const onconfirm = vi.fn();
    render(ConfirmDialog, {
      props: { ...base, open: true, requirePhrase: 'Films', onconfirm }
    });
    await settle();
    const input = screen.getByRole('textbox', { name: 'Type Films to confirm' });
    const confirm = screen.getByRole('button', { name: 'Delete' });
    expect(input).toHaveFocus();
    expect(confirm).toBeDisabled();

    await userEvent.type(input, 'films');
    expect(confirm).toBeDisabled();
    await userEvent.keyboard('{Enter}');
    expect(onconfirm).not.toHaveBeenCalled();

    await userEvent.clear(input);
    await userEvent.type(input, 'Films');
    expect(confirm).toBeEnabled();
    await userEvent.click(confirm);
    expect(onconfirm).toHaveBeenCalledOnce();
  });

  it('zet hoofdletters, spellingcontrole en aanvullen uit op het zinveld', async () => {
    render(ConfirmDialog, {
      props: {
        ...base,
        open: true,
        requirePhrase: 'Films',
        phraseLabel: 'Type the library name',
        onconfirm: vi.fn()
      }
    });
    const input = screen.getByRole('textbox', { name: 'Type the library name' });
    expect(input).toHaveAttribute('autocapitalize', 'off');
    expect(input).toHaveAttribute('spellcheck', 'false');
    expect(input).toHaveAttribute('autocomplete', 'off');
  });

  it('sluit op een klik op de scrim maar niet tijdens bezig', async () => {
    const oncancel = vi.fn();
    const { container, rerender } = render(ConfirmDialog, {
      props: { ...base, open: true, busy: true, onconfirm: vi.fn(), oncancel }
    });
    await userEvent.click(container.querySelector('.cd__scrim')!);
    expect(oncancel).not.toHaveBeenCalled();
    expect(screen.getByRole('button', { name: 'Delete' })).toBeDisabled();

    await rerender({ busy: false });
    await userEvent.click(container.querySelector('.cd__scrim')!);
    expect(oncancel).toHaveBeenCalledOnce();
  });

  it('houdt de focusval vast als bezig het gefocuste veld uitschakelt', async () => {
    trigger();
    const oncancel = vi.fn();
    const { rerender } = render(ConfirmDialog, {
      props: { ...base, open: true, requirePhrase: 'Films', onconfirm: vi.fn(), oncancel }
    });
    await settle();
    const input = screen.getByRole('textbox', { name: 'Type Films to confirm' });
    expect(input).toHaveFocus();

    // Een browser verplaatst de focus van een uitgeschakeld element naar body.
    // jsdom doet dat niet en blur() op een uitgeschakeld veld is daar een no-op,
    // dus de focus gaat met de hand naar body vlak voordat bezig aangaat.
    input.blur();
    await rerender({ busy: true });
    expect(document.body).toHaveFocus();
    expect(input).toBeDisabled();

    const dialog = screen.getByRole('dialog');
    const cancel = screen.getByRole('button', { name: 'Cancel' });
    await userEvent.tab();
    expect(cancel).toHaveFocus();
    await userEvent.tab();
    expect(cancel).toHaveFocus();

    cancel.blur();
    await userEvent.tab({ shift: true });
    expect(dialog).toContainElement(document.activeElement as HTMLElement);

    // Escape annuleert tijdens bezig nog steeds niet, ook niet vanaf body.
    (document.activeElement as HTMLElement).blur();
    await userEvent.keyboard('{Escape}');
    expect(oncancel).not.toHaveBeenCalled();
    expect(screen.getByRole('dialog')).toBeInTheDocument();

    await rerender({ busy: false });
    await userEvent.keyboard('{Escape}');
    expect(oncancel).toHaveBeenCalledOnce();
  });
});
