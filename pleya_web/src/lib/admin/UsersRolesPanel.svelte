<!--
  De twee toelichtingen onder de tabel van scherm 26: Rollen (de vier rollen
  van DEC-119 in een lijst) en Wat je hier niet ziet. De tweede noemt ook wat
  het contract niet toont, zodat niemand een ontbrekend gegeven voor een fout
  houdt.
-->
<script lang="ts">
  import type { Role } from '../api/types';
  import Panel from '../components/Panel.svelte';
  import { t } from '../i18n';
  import { roleHint, roleLabel } from './users';

  const roles: Role[] = ['owner', 'admin', 'member', 'restricted'];
</script>

<div class="pair">
  <Panel>
    {#snippet title()}{t('admin.users.roles.title')}{/snippet}
    <dl class="roles">
      {#each roles as role (role)}
        <dt>{roleLabel(role)}</dt>
        <dd>{roleHint(role)}</dd>
      {/each}
    </dl>
  </Panel>
  <Panel>
    {#snippet title()}{t('admin.users.hidden.title')}{/snippet}
    <p class="note">{t('admin.users.hidden.body')}</p>
  </Panel>
</div>

<style>
  .pair {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 14px;
    margin-top: 14px;
  }

  .roles {
    display: grid;
    grid-template-columns: max-content minmax(0, 1fr);
    gap: 10px 24px;
    margin: 0;
    font-size: 14px;
    line-height: 1.4;
  }

  dt {
    color: var(--ink-3);
  }

  dd {
    margin: 0;
    color: var(--ink-2);
  }

  .note {
    margin: 0;
    font-size: 13px;
    line-height: 1.5;
    color: var(--ink-3);
  }

  @media (max-width: 899px) {
    .pair {
      grid-template-columns: minmax(0, 1fr);
    }

    .roles {
      grid-template-columns: minmax(0, 1fr);
      gap: 2px;
    }

    dd {
      margin-bottom: 10px;
    }
  }
</style>
