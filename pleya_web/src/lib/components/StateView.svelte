<!--
  Eén component voor leeg en fout, net als `lib/widgets/state_view.dart` in de
  app: hetzelfde icoon-boven-titel-boven-tekst, met een optionele herhaalknop.
  Style komt volledig uit de tokens. Laden is hier weggehaald: dat is een
  skelet in de maten van de inhoud (SkeletonPage), geen spinner.
-->
<script lang="ts">
  import type { Snippet } from 'svelte';
  import { t } from '../i18n';

  interface Props {
    kind?: 'empty' | 'error';
    title?: string;
    message?: string;
    onRetry?: (() => void) | undefined;
    retryLabel?: string;
    compact?: boolean;
    children?: Snippet;
  }

  let {
    kind = 'empty',
    title,
    message,
    onRetry,
    retryLabel = t('common.retry'),
    compact = false,
    children
  }: Props = $props();

  const resolvedTitle = $derived(
    title ?? (kind === 'error' ? t('states.errorTitle') : t('states.emptyTitle'))
  );
</script>

<div class="state" class:state--compact={compact} role={kind === 'error' ? 'alert' : undefined}>
  <svg class="state__icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">
    {#if kind === 'error'}
      <path
        fill="currentColor"
        d="M12 2 1 21h22zm0 5 8.5 12h-17zm-1 4v5h2v-5zm0 6v2h2v-2z"
      />
    {:else}
      <path
        fill="currentColor"
        d="M3 5h18v9h-5a4 4 0 0 1-8 0H3zm2 2v5h4.5a2.5 2.5 0 0 0 5 0H19V7zM3 16h18v3H3z"
      />
    {/if}
  </svg>

  <p class="state__title t-title">{resolvedTitle}</p>
  {#if message}
    <p class="state__message t-body">{message}</p>
  {/if}
  {#if children}
    <div class="state__extra">{@render children()}</div>
  {/if}
  {#if onRetry}
    <button type="button" class="btn btn--secondary state__retry" onclick={onRetry}>
      {retryLabel}
    </button>
  {/if}
</div>

<style>
  .state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: var(--space-half);
    text-align: center;
    padding: var(--space-2);
    min-height: 40vh;
  }

  .state--compact {
    min-height: 0;
    padding: var(--space);
  }

  .state__icon {
    width: 48px;
    height: 48px;
    color: var(--text-muted);
    margin-bottom: var(--space-half);
  }

  .state--compact .state__icon {
    width: 32px;
    height: 32px;
  }

  .state__title {
    color: var(--text);
  }

  .state__message {
    color: var(--text-muted);
    max-width: 46ch;
  }

  .state__retry,
  .state__extra {
    margin-top: var(--space);
  }
</style>
