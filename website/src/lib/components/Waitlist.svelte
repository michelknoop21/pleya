<script lang="ts">
  import { WAITLIST_WEBHOOK_URL, WAITLIST_FALLBACK_EMAIL } from '$lib/config';
  import CheckIcon from '~icons/heroicons/check-circle-solid';

  let email = $state('');
  let status = $state<'idle' | 'submitting' | 'done' | 'error'>('idle');

  const inputId = 'waitlist-email';
  const hasWebhook = WAITLIST_WEBHOOK_URL.trim().length > 0;

  function mailtoHref(value: string) {
    const subject = encodeURIComponent('Pleya waitlist');
    const body = encodeURIComponent(
      value ? `Please add me to the Pleya waitlist: ${value}` : 'Please add me to the Pleya waitlist.'
    );
    return `mailto:${WAITLIST_FALLBACK_EMAIL}?subject=${subject}&body=${body}`;
  }

  async function handleSubmit(event: SubmitEvent) {
    event.preventDefault();
    if (!email.trim()) return;

    if (!hasWebhook) {
      // No backend configured, hand off to the visitor's mail client.
      window.location.href = mailtoHref(email);
      status = 'done';
      return;
    }

    status = 'submitting';
    try {
      const res = await fetch(WAITLIST_WEBHOOK_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: email.trim(), source: 'pleya.app' })
      });
      if (!res.ok) throw new Error(String(res.status));
      status = 'done';
    } catch {
      status = 'error';
    }
  }
</script>

<div class="waitlist">
  {#if status === 'done'}
    <p class="waitlist-success" role="status">
      <CheckIcon />
      <span>You're on the list. We'll email you when Pleya opens up.</span>
    </p>
  {:else}
    <form
      class="waitlist-form"
      action={mailtoHref(email)}
      method="get"
      onsubmit={handleSubmit}
      novalidate={false}
    >
      <label class="waitlist-label" for={inputId}>Get notified when Pleya launches</label>
      <div class="waitlist-row">
        <input
          id={inputId}
          name="email"
          type="email"
          inputmode="email"
          autocomplete="email"
          required
          placeholder="you@example.com"
          bind:value={email}
          class="waitlist-input"
          aria-describedby={status === 'error' ? 'waitlist-error' : undefined}
        />
        <button type="submit" class="waitlist-submit" disabled={status === 'submitting'}>
          {status === 'submitting' ? 'Adding…' : 'Notify me'}
        </button>
      </div>
      {#if status === 'error'}
        <p id="waitlist-error" class="waitlist-error" role="alert">
          Something went wrong. Please try again, or email {WAITLIST_FALLBACK_EMAIL}.
        </p>
      {/if}
    </form>
  {/if}
</div>

<style>
  .waitlist {
    max-width: 26rem;
  }

  .waitlist-label {
    display: block;
    margin-bottom: 0.5rem;
    color: var(--color-text-muted);
    font-size: 0.8125rem;
    font-weight: 500;
    letter-spacing: 0.01em;
  }

  .waitlist-row {
    display: flex;
    gap: 0.5rem;
  }

  .waitlist-input {
    flex: 1;
    min-width: 0;
    height: 3rem;
    padding: 0 1rem;
    border: 1px solid var(--color-border);
    border-radius: 0.75rem;
    background: var(--color-surface);
    color: var(--color-text);
    font-size: 1rem;
    transition: border-color 150ms ease, box-shadow 150ms ease;
  }

  .waitlist-input::placeholder {
    color: var(--color-text-faint);
  }

  .waitlist-input:focus-visible {
    outline: none;
    border-color: var(--color-accent);
    box-shadow: 0 0 0 3px var(--color-accent-glow);
  }

  .waitlist-submit {
    flex-shrink: 0;
    height: 3rem;
    padding-inline: 1.25rem;
    border-radius: 0.75rem;
    background: var(--gradient-brand);
    color: #fff;
    font-size: 0.9375rem;
    font-weight: 600;
    transition: filter 150ms ease, transform 150ms ease;
  }

  .waitlist-submit:hover:not(:disabled) {
    filter: brightness(1.08);
  }

  .waitlist-submit:active:not(:disabled) {
    transform: translateY(1px);
  }

  .waitlist-submit:disabled {
    opacity: 0.6;
  }

  .waitlist-submit:focus-visible,
  .waitlist-input:focus-visible {
    outline-offset: 2px;
  }

  .waitlist-error {
    margin-top: 0.5rem;
    color: #ffb4ad;
    font-size: 0.8125rem;
  }

  .waitlist-success {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    color: var(--color-text);
    font-size: 0.9375rem;
    font-weight: 500;
  }

  .waitlist-success :global(svg) {
    width: 1.375rem;
    height: 1.375rem;
    flex-shrink: 0;
    color: var(--color-amber);
  }
</style>
