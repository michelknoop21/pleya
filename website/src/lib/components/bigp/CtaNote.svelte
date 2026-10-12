<script lang="ts">
  import { betaLinkReady, cta, WAITLIST_FALLBACK_EMAIL } from '$lib/config';

  let copied = $state(false);
  let timer: ReturnType<typeof setTimeout>;
  async function copy() {
    try {
      await navigator.clipboard.writeText(WAITLIST_FALLBACK_EMAIL);
      copied = true;
      clearTimeout(timer);
      timer = setTimeout(() => (copied = false), 2500);
    } catch {
      // No clipboard access: the address is a link and selectable text right next to the button.
    }
  }
</script>

<!-- What the button does, and a way through for a device without a mail app. -->
<p class="cta-note bp-note">
  {cta.note}
  {#if !betaLinkReady}
    No mail app here? Write to <a href="mailto:{WAITLIST_FALLBACK_EMAIL}">{WAITLIST_FALLBACK_EMAIL}</a>
    <button type="button" onclick={copy} aria-live="polite">{copied ? 'Copied' : 'Copy address'}</button>
  {/if}
</p>

<style>
  .bp-note { max-width: 30rem; color: var(--muted); font-size: 0.88rem; line-height: 1.6; }
  a { color: var(--ink); text-decoration: underline; text-decoration-color: var(--amber); text-underline-offset: 0.3em; }
  button { margin-left: 0.4rem; padding: 0.35rem 0.8rem; border-radius: 999px; background: rgba(255, 255, 255, 0.08); color: var(--ink); font-size: 0.82rem; font-weight: 600; transition: background-color 0.4s var(--ease); }
  button:hover { background: rgba(255, 255, 255, 0.16); }
</style>
