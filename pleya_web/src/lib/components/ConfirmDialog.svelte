<!--
  Bevestiging van een ingrijpende actie (`.modal` en `.scrim-full` in web.css,
  mockup 23): een kaart van max. 520 breed midden op een scrim van 62 procent,
  en onder 900 een sheet vanaf de onderrand met de knoppen over de volle
  breedte, de veilige knop onderaan.

  Met `requirePhrase` (K-rij 16) moet je eerst een zin letterlijk overtypen;
  de bevestigknop blijft tot een exacte, hoofdlettergevoelige match
  uitgeschakeld. Het invoerveld zet autocapitalize, spellcheck en autocomplete
  uit, anders maakt een telefoon van "films" ongevraagd "Films" en matcht het
  nooit. Field levert label en foutpad via zijn snippet, de invoer zelf staat
  hier zodat Field geen doorgeefluik voor losse attributen hoeft te worden.

  Bewust een eigen div met role="dialog" en geen <dialog>: showModal en de
  inertheid erachter bestaan in jsdom niet, en dan bewijzen de tests niets. De
  focus gaat bij openen naar het veld (of de veilige knop), Tab blijft binnen
  de kaart, Escape en de scrim annuleren, en bij sluiten keert de focus terug
  naar waar hij vandaan kwam.
-->
<script lang="ts">
  import { tick, type Snippet } from 'svelte';

  import { t } from '../i18n';
  import Field from './Field.svelte';
  import { lockScroll } from '../util/scrollLock';

  interface Props {
    open?: boolean;
    title: string;
    message?: string;
    /** Extra inhoud onder de tekst, bijvoorbeeld een opsomming van gevolgen. */
    children?: Snippet;
    confirmLabel: string;
    /** Icoon voor de bevestigknop, zoals de prullenbak in mockup 23. */
    confirmIcon?: Snippet;
    cancelLabel?: string;
    /** Zin die je moet overtypen voor de bevestigknop werkt. */
    requirePhrase?: string;
    phraseLabel?: string;
    danger?: boolean;
    busy?: boolean;
    onconfirm: () => void;
    oncancel?: () => void;
  }

  let {
    open = $bindable(false),
    title,
    message,
    children,
    confirmLabel,
    confirmIcon,
    cancelLabel = t('dialog.cancel'),
    requirePhrase,
    phraseLabel,
    danger = true,
    busy = false,
    onconfirm,
    oncancel
  }: Props = $props();

  const uid = $props.id();
  const titleId = `${uid}-title`;
  const messageId = `${uid}-message`;

  let card: HTMLDivElement | undefined = $state();
  let cancelButton: HTMLButtonElement | undefined = $state();
  let typed = $state('');

  const matches = $derived(!requirePhrase || typed === requirePhrase);
  const canConfirm = $derived(matches && !busy);

  const FOCUSABLE =
    'a[href], button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea:not(:disabled), [tabindex]:not([tabindex="-1"])';

  // Eigen effect, los van de focus: de pagina erachter scrolt niet mee zolang
  // de dialoog open is, ook niet met een veeg op de scrim. De cleanup draait bij
  // sluiten én bij unmount.
  $effect(() => {
    if (!open) return;
    return lockScroll();
  });

  $effect(() => {
    if (!open) return;
    const previous = document.activeElement as HTMLElement | null;
    typed = '';
    void tick().then(() => {
      const field = card?.querySelector<HTMLInputElement>('input');
      (field ?? cancelButton)?.focus();
    });
    // Draait als `open` weer onwaar wordt of de dialoog verdwijnt.
    return () => previous?.focus?.();
  });

  function cancel(): void {
    if (busy) return;
    open = false;
    oncancel?.();
  }

  function submit(event: SubmitEvent): void {
    event.preventDefault();
    if (canConfirm) onconfirm();
  }

  // Luistert op document en niet op de kaart: zet `busy` het gefocuste veld of
  // de bevestigknop uit, dan valt de focus naar body en zou een handler op de
  // kaart Tab en Escape niet meer zien.
  function keydown(event: KeyboardEvent): void {
    if (!open) return;
    if (event.key === 'Escape') {
      event.preventDefault();
      event.stopPropagation();
      cancel();
      return;
    }
    if (event.key !== 'Tab' || !card) return;
    const items = [...card.querySelectorAll<HTMLElement>(FOCUSABLE)];
    if (items.length === 0) return;
    const first = items[0]!;
    const last = items[items.length - 1]!;
    const active = document.activeElement;
    if (event.shiftKey && (active === first || !card.contains(active))) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && (active === last || !card.contains(active))) {
      event.preventDefault();
      first.focus();
    }
  }
</script>

<svelte:document onkeydown={keydown} />

{#if open}
  <div class="cd__scrim" aria-hidden="true" onclick={cancel}></div>
  <div
    class="cd"
    role="dialog"
    aria-modal="true"
    aria-labelledby={titleId}
    aria-describedby={message ? messageId : undefined}
    tabindex="-1"
    bind:this={card}
  >
    <h2 class="cd__title" id={titleId}>{title}</h2>
    {#if message}
      <p class="cd__text" id={messageId}>{message}</p>
    {/if}
    {#if children}
      <div class="cd__body">{@render children()}</div>
    {/if}

    <form class="cd__form" onsubmit={submit}>
      {#if requirePhrase}
        <div class="cd__phrase">
          <Field label={phraseLabel ?? t('dialog.typeToConfirm', { phrase: requirePhrase })}>
            {#snippet children(control)}
              <input
                id={control.id}
                type="text"
                aria-describedby={control.describedby}
                autocapitalize="off"
                autocomplete="off"
                spellcheck="false"
                disabled={busy}
                bind:value={typed}
              />
            {/snippet}
          </Field>
        </div>
      {/if}

      <div class="cd__foot">
        <button type="button" class="btn btn--ghost" bind:this={cancelButton} onclick={cancel}>
          {cancelLabel}
        </button>
        <button
          type="submit"
          class="btn"
          class:btn--danger-solid={danger}
          disabled={!canConfirm}
          aria-busy={busy ? 'true' : undefined}
        >
          {#if confirmIcon}
            <span class="cd__icon" aria-hidden="true">{@render confirmIcon()}</span>
          {/if}
          {confirmLabel}
        </button>
      </div>
    </form>
  </div>
{/if}

<style>
  .cd__scrim {
    position: fixed;
    inset: 0;
    z-index: 60;
    /* rgba(0,0,0,.62) uit web.css `.scrim-full`, in elk thema zwart. */
    background: rgba(0, 0, 0, 0.62);
  }

  .cd {
    position: fixed;
    top: 50%;
    left: 50%;
    z-index: 70;
    width: min(520px, calc(100vw - 32px));
    max-height: calc(100dvh - 32px);
    overflow-y: auto;
    padding: 26px 28px;
    border-radius: var(--radius-hero);
    background: var(--surface);
    box-shadow: 0 30px 80px rgba(0, 0, 0, 0.6);
    transform: translate(-50%, -50%);
  }

  .cd:focus {
    outline: none;
  }

  .cd__title {
    font-size: 20px;
    font-weight: 700;
    line-height: 1.3;
    color: var(--ink);
  }

  .cd__text,
  .cd__body {
    margin-top: 8px;
    font-size: 14px;
    line-height: 1.45;
    color: var(--ink-2);
  }

  .cd__phrase {
    margin-top: 12px;
  }

  .cd__icon {
    display: grid;
    place-items: center;
    width: 18px;
    height: 18px;
  }

  .cd__icon :global(svg) {
    width: 100%;
    height: 100%;
  }

  .cd__foot {
    display: flex;
    justify-content: flex-end;
    gap: 10px;
    margin-top: 22px;
  }

  @media (max-width: 899px) {
    .cd {
      top: auto;
      bottom: 0;
      left: 0;
      width: 100%;
      max-height: 90dvh;
      padding-bottom: calc(34px + env(safe-area-inset-bottom));
      border-radius: var(--radius-md) var(--radius-md) 0 0;
      transform: none;
    }

    /* De veilige knop onderaan, onder de duim (mockup 23). */
    .cd__foot {
      flex-direction: column-reverse;
    }

    .cd__foot .btn {
      width: 100%;
    }
  }
</style>
