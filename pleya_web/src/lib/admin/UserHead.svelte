<!--
  De kop van de pagina van één gebruiker: kruimelpad, een rondje met de eerste
  letter, de naam, en eronder de rol, laatst actief en het aantal toestellen.
  Rechts Wachtwoord opnieuw instellen en Opslaan; die gelden voor de hele
  pagina en staan daarom boven de tabs.

  Laatst actief en toestellen komen uit de sessies. Waren die niet te lezen,
  dan staan beide er niet. Een foto of weergavenaam kent het contract niet, dus
  het rondje toont alleen de eerste letter van de gebruikersnaam.
-->
<script lang="ts">
  import type { UserSession } from '../api/adminUsers';
  import type { User } from '../api/types';
  import StatusPill from '../components/StatusPill.svelte';
  import { plural, t } from '../i18n';
  import { deviceSessions, lastActiveText, roleLabel, roleTone } from './users';

  interface Props {
    user: User;
    /** Null als de sessies niet te lezen waren. */
    sessions: UserSession[] | null;
    listHref: string;
    canReset: boolean;
    dirty: boolean;
    saving: boolean;
    onreset: () => void;
    /** Het formulier van de tab Toegang; Opslaan verstuurt dat. */
    formId: string;
  }

  let { user, sessions, listHref, canReset, dirty, saving, onreset, formId }: Props = $props();

  const initial = $derived((Array.from(user.username.trim())[0] ?? '').toUpperCase());
  const devices = $derived(sessions ? deviceSessions(sessions).length : null);
</script>

<header class="head">
  <nav class="crumb" aria-label={t('admin.lib.crumbs')}>
    <ol>
      <li><a href="/admin">{t('admin.title')}</a></li>
      <li><a href={listHref}>{t('admin.nav.users')}</a></li>
      <li><span aria-current="page">{user.username}</span></li>
    </ol>
  </nav>
  <div class="row">
    <span class="avatar" aria-hidden="true">{initial}</span>
    <div class="who">
      <h1 class="title">{user.username}</h1>
      <div class="meta">
        <StatusPill size="sm" tone={roleTone(user.role)} label={roleLabel(user.role)} />
        {#if sessions !== null && devices !== null}
          <span>{t('admin.users.head.lastActive', { value: lastActiveText(sessions) })}</span>
          <StatusPill
            variant="dot"
            tone={devices > 0 ? 'ok' : 'idle'}
            label={devices > 0
              ? plural('admin.users.signedIn', devices)
              : t('admin.users.signedIn.none')}
          />
        {/if}
      </div>
    </div>
    <div class="actions">
      <button type="button" class="btn btn--secondary" disabled={!canReset} onclick={onreset}>
        {t('admin.users.account.reset')}
      </button>
      <a class="btn btn--ghost" href={listHref}>{t('dialog.cancel')}</a>
      <button
        type="submit"
        form={formId}
        class="btn"
        disabled={!dirty || saving}
        aria-busy={saving ? 'true' : undefined}
      >
        {t('admin.users.action.save')}
      </button>
    </div>
  </div>
</header>

<style>
  .head {
    margin-bottom: 18px;
  }

  /* Zelfde kruimelpad als AdminPageHead; die kop kent geen rondje of metaregel. */
  .crumb ol {
    display: flex;
    flex-wrap: wrap;
    gap: 4px;
    margin: 0 0 10px;
    padding: 0;
    list-style: none;
    font-size: 13px;
    color: var(--ink-3);
  }

  .crumb li + li::before {
    content: '';
    display: inline-block;
    margin: 0 6px 0 2px;
    border-block: 3.5px solid transparent;
    border-left: 4px solid currentColor;
    vertical-align: 1px;
  }

  .crumb a {
    color: inherit;
  }

  @media (hover: hover) {
    .crumb a:hover {
      color: var(--ink);
    }
  }

  .row {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 14px 18px;
  }

  .avatar {
    display: grid;
    flex: none;
    place-items: center;
    width: 64px;
    height: 64px;
    border-radius: var(--radius-pill);
    background: var(--elevated);
    font-size: 26px;
    font-weight: 700;
    color: var(--ink);
  }

  .who {
    display: grid;
    flex: 1 1 240px;
    gap: 6px;
    min-width: 0;
  }

  .title {
    margin: 0;
    font-size: 34px;
    font-weight: 700;
    line-height: 1.1;
    letter-spacing: -0.01em;
    color: var(--ink);
    overflow-wrap: anywhere;
  }

  .meta {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 6px 14px;
    font-size: 13px;
    color: var(--ink-3);
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }

  @media (max-width: 899px) {
    .avatar {
      width: 48px;
      height: 48px;
      font-size: 20px;
    }

    .who {
      flex-basis: 0;
    }

    .title {
      font-size: 26px;
    }

    .actions {
      flex: 1 1 100%;
    }

    .actions .btn {
      flex: 1 1 auto;
    }
  }
</style>
