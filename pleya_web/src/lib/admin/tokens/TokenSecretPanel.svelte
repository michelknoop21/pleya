<!--
  Het geheim van een net aangemaakt token, één keer (34). De server toont het
  alleen in het antwoord van `POST /auth/api-tokens` en bewaart de hash.

  Regels voor dit paneel: het geheim leeft alleen in de prop die de pagina hier
  doorgeeft, en nergens anders. Het gaat niet naar localStorage, sessionStorage,
  de URL, de console of een log; de kopieerknop schrijft het naar het
  klembord en meer niet. Sluiten roept `onclose` aan, de pagina wist het uit
  haar state en het paneel verdwijnt uit de DOM. De "Gekopieerd"-melding is een
  boolean en bevat het geheim niet.
-->
<script lang="ts">
  import Alert from '../../components/Alert.svelte';
  import Panel from '../../components/Panel.svelte';
  import { t } from '../../i18n';
  import { formatDate } from '../../util/format';
  import { scopeLabel } from './tokens';

  interface Props {
    secret: string;
    name: string;
    scope: string;
    expiresAt: string;
    onclose: () => void;
  }

  let { secret, name, scope, expiresAt, onclose }: Props = $props();

  let copied = $state(false);
  let blocked = $state(false);
  let box = $state<HTMLElement | null>(null);

  async function copy(): Promise<void> {
    copied = false;
    blocked = false;
    try {
      await navigator.clipboard.writeText(secret);
      copied = true;
    } catch {
      blocked = true;
      // Selecteer het geheim, zodat Cmd+C of Ctrl+C het meteen pakt.
      if (box) {
        const range = document.createRange();
        range.selectNodeContents(box);
        const selection = window.getSelection();
        selection?.removeAllRanges();
        selection?.addRange(range);
      }
    }
  }
</script>

<section class="secret" aria-labelledby="tok-secret-title" data-testid="token-secret">
  <Panel tone="warn">
    {#snippet title()}<span id="tok-secret-title">{t('admin.tok.secret.title')}</span>{/snippet}
    <p class="lead">{t('admin.tok.secret.body')}</p>
    <p class="meta">
      {t('admin.tok.secret.meta', {
        name,
        scope: scopeLabel(scope),
        date: formatDate(expiresAt) ?? ''
      })}
    </p>
    <div class="row">
      <span class="visually-hidden" id="tok-secret-label">{t('admin.tok.secret.label')}</span>
      <code class="value" bind:this={box} aria-labelledby="tok-secret-label">{secret}</code>
      <button type="button" class="btn btn--secondary" onclick={() => void copy()}>
        {copied ? t('admin.tok.secret.copied') : t('admin.tok.secret.copy')}
      </button>
    </div>
    {#if blocked}
      <div class="alert"><Alert tone="info">{t('admin.tok.secret.copyFailed')}</Alert></div>
    {/if}
    <div class="foot">
      <p class="gone">{t('admin.tok.secret.gone')}</p>
      <button type="button" class="btn" onclick={onclose}>{t('admin.tok.secret.done')}</button>
    </div>
  </Panel>
</section>

<style>
  .secret {
    margin-bottom: 16px;
  }

  .lead {
    margin: 0 0 6px;
    font-size: 14px;
    line-height: 1.5;
    color: var(--ink-2);
  }

  .meta {
    margin: 0 0 14px;
    font-size: 13px;
    color: var(--ink-3);
    overflow-wrap: anywhere;
  }

  .row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 10px;
  }

  .value {
    flex: 1 1 260px;
    min-width: 0;
    padding: 12px 14px;
    border: 1px solid var(--hairline);
    border-radius: 12px;
    background: var(--inset-bg);
    font-family: var(--font-mono);
    font-size: 13.5px;
    color: var(--ink);
    overflow-wrap: anywhere;
    user-select: all;
  }

  .alert {
    margin-top: 10px;
  }

  .foot {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
    margin-top: 16px;
  }

  .gone {
    margin: 0;
    font-size: 12.5px;
    color: var(--ink-3);
  }
</style>
