<!--
  De beheerzijbalk (web.css `.admin-nav`, schermen 20 tot 38): kop
  "Serverbeheer", de tien secties met icoon, een scheidslijn en "Terug naar
  Pleya". De actieve sectie krijgt een vlak in --fill-2 en volle inkt. Plakt
  onder de topnav mee bij scrollen. Badges per sectie volgen later (S10.1
  laat ze optioneel).
-->
<script lang="ts">
  import AdminIcon from './AdminIcon.svelte';
  import { ADMIN_SECTIONS, type AdminSectionId } from '../admin/sections';
  import { t } from '../i18n';

  interface Props {
    active: AdminSectionId | null;
  }

  let { active }: Props = $props();
</script>

<nav class="admin-nav" aria-label={t('admin.title')}>
  <p class="admin-nav__head">{t('admin.title')}</p>
  <ul>
    {#each ADMIN_SECTIONS as section (section.id)}
      <li>
        <a
          class="admin-nav__link"
          class:admin-nav__link--on={section.id === active}
          href={section.href}
          aria-current={section.id === active ? 'page' : undefined}
        >
          <AdminIcon name={section.icon} />
          <span>{t(section.label)}</span>
        </a>
      </li>
    {/each}
  </ul>
  <div class="admin-nav__sep" role="presentation"></div>
  <a class="admin-nav__link" href="/">
    <AdminIcon name="chevl" />
    <span>{t('admin.nav.back')}</span>
  </a>
</nav>

<style>
  .admin-nav {
    position: sticky;
    top: calc(var(--nav-h) + 8px);
  }

  ul {
    margin: 0;
    padding: 0;
    list-style: none;
  }

  .admin-nav__head {
    margin: 8px 0 8px 12px;
    font-size: 12px;
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--ink-3);
  }

  .admin-nav__link {
    display: flex;
    align-items: center;
    gap: 12px;
    height: 40px;
    padding: 0 12px;
    border-radius: 10px;
    font-size: 14px;
    color: var(--ink-2);
  }

  .admin-nav__link span {
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .admin-nav__link--on {
    background: var(--fill-2);
    color: var(--ink);
    font-weight: 600;
  }

  @media (hover: hover) {
    .admin-nav__link:not(.admin-nav__link--on):hover {
      background: var(--fill);
      color: var(--ink);
    }
  }

  .admin-nav__sep {
    height: 1px;
    margin: 10px 12px;
    background: var(--hairline-strong);
  }
</style>
