<!--
  Serverbeheer, Agents en API-tokens (northstar 34): de tokens van alle
  gebruikers, een formulier voor een nieuw token, de MCP-status en de laatste
  acties van agents uit het auditlog.

  Beveiliging van dit scherm, in volgorde van belang:
  - Het geheim van een nieuw token staat alleen in `created` en in het paneel
    dat het toont. Sluiten, de pagina verlaten of een tweede token wissen het;
    een tweede token is bovendien niet aan te maken zolang het eerste open
    staat. Het gaat nergens heen behalve het klembord (zie TokenSecretPanel).
  - Intrekken vraagt een bevestiging, en een token met beheerbereik aanmaken
    ook. Een weigering van de server laat de lijst zoals hij was.
  - Meldt de server geen `capabilities.api_tokens`, dan vraagt dit scherm niets
    van de tokenroutes en legt het uit waarom.
-->
<script lang="ts">
  import { adminApi } from '../../api/admin';
  import { adminTokensApi, type ApiTokenCreated } from '../../api/adminTokens';
  import { adminUsersApi } from '../../api/adminUsers';
  import { describeError } from '../../api/errors';
  import Alert from '../../components/Alert.svelte';
  import ConfirmDialog from '../../components/ConfirmDialog.svelte';
  import SkeletonPage from '../../components/SkeletonPage.svelte';
  import StateView from '../../components/StateView.svelte';
  import AdminIcon from '../../components/AdminIcon.svelte';
  import { t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import AdminPageHead from '../AdminPageHead.svelte';
  import LibraryProblemAlert from '../LibraryProblemAlert.svelte';
  import type { LibraryProblem } from '../libraryErrors';
  import AgentAuditPanel from './AgentAuditPanel.svelte';
  import McpPanel from './McpPanel.svelte';
  import TokenCreatePanel from './TokenCreatePanel.svelte';
  import TokenSecretPanel from './TokenSecretPanel.svelte';
  import { tokenProblem } from './tokenErrors';
  import TokensTable from './TokensTable.svelte';
  import { isBroadScope, loadTokens, sortRows, type TokenRow, type TokensData } from './tokens';

  const supported = $derived(session.capabilities?.api_tokens === true);

  let data = $state<TokensData | null>(null);
  let failure = $state<string | null>(null);
  let attempt = $state(0);
  let problem = $state<LibraryProblem | null>(null);
  let retry = $state<() => void>(() => {});

  /** Het geheim van het net aangemaakte token. Dit is de enige plek waar het leeft. */
  let created = $state<ApiTokenCreated | null>(null);
  let creating = $state(false);

  let broadOpen = $state(false);
  let broadAnswer: ((ok: boolean) => void) | null = null;

  let revokeTarget = $state<TokenRow | null>(null);
  let revokeOpen = $state(false);
  let revoking = $state<Record<string, boolean>>({});

  $effect(() => {
    void attempt;
    if (!supported) return;
    const controller = new AbortController();
    loadTokens(
      session.client,
      adminApi(session.client),
      adminTokensApi(session.client),
      controller.signal
    )
      .then((result) => {
        data = result;
        failure = null;
      })
      .catch((err: unknown) => {
        if (!controller.signal.aborted) failure = describeError(err);
      });
    return () => controller.abort();
  });

  // De pagina verlaten wist het geheim uit het geheugen.
  $effect(() => () => {
    created = null;
  });

  function confirmBroad(): Promise<boolean> {
    broadOpen = true;
    return new Promise((resolve) => {
      broadAnswer = resolve;
    });
  }

  function answerBroad(ok: boolean): void {
    broadOpen = false;
    broadAnswer?.(ok);
    broadAnswer = null;
  }

  async function create(request: { name: string; scope: string; days: number }): Promise<boolean> {
    if (creating) return false;
    if (isBroadScope(request.scope) && !(await confirmBroad())) return false;
    creating = true;
    problem = null;
    try {
      const result = await adminTokensApi(session.client).createToken({
        name: request.name,
        scope: request.scope as ApiTokenCreated['token']['scope'],
        expires_in_days: request.days
      });
      created = result;
      const owner = data?.users.find((u) => u.id === result.token.user_id) ?? session.me;
      if (data && owner) data = { ...data, rows: sortRows([...data.rows, { token: result.token, owner }]) };
      return true;
    } catch (err) {
      // Het formulier bewaart zijn invoer: opnieuw proberen is opnieuw aanmaken, geen eigen knop.
      const found = tokenProblem(err, 'create', request.name);
      problem = found.wayOut === 'retry' ? { ...found, wayOut: 'none' } : found;
      return false;
    } finally {
      creating = false;
    }
  }

  function askRevoke(row: TokenRow): void {
    revokeTarget = row;
    revokeOpen = true;
  }

  async function revoke(): Promise<void> {
    const row = revokeTarget;
    if (!row) return;
    revoking[row.token.id] = true;
    problem = null;
    try {
      await adminUsersApi(session.client).revokeSession(row.token.id);
      revokeOpen = false;
      if (data) data = { ...data, rows: data.rows.filter((r) => r.token.id !== row.token.id) };
    } catch (err) {
      revokeOpen = false;
      problem = tokenProblem(err, 'revoke', row.token.name);
      retry = () => void revoke();
    } finally {
      revoking[row.token.id] = false;
    }
  }
</script>

<AdminPageHead
  title={t('admin.tok.title')}
  crumbs={[
    { label: t('admin.title'), href: '/admin' },
    { label: t('admin.nav.security'), href: '/admin/security' },
    { label: t('admin.tok.title') }
  ]}
>
  {#snippet actions()}
    {#if supported}
      <a class="btn btn--sm" href="#tok-new">
        <AdminIcon name="plus" size={16} />{t('admin.tok.action.create')}
      </a>
    {/if}
  {/snippet}
</AdminPageHead>

{#if !supported}
  <StateView title={t('admin.tok.off.title')} message={t('admin.tok.off.body')}>
    {#snippet actions()}
      <a class="btn btn--secondary" href="/admin/security">{t('admin.tok.off.back')}</a>
    {/snippet}
  </StateView>
{:else}
  {#if problem}
    <div class="msg">
      <LibraryProblemAlert {problem} onretry={() => retry()} onreload={() => (attempt += 1)} />
    </div>
  {/if}

  {#if created}
    <TokenSecretPanel
      secret={created.secret}
      name={created.token.name}
      scope={created.token.scope}
      expiresAt={created.token.expires_at}
      onclose={() => (created = null)}
    />
  {/if}

  {#if data}
    {#if data.unreadable.length > 0}
      <div class="msg">
        <Alert tone="warn">
          {t('admin.tok.list.unreadable', { names: data.unreadable.map((u) => u.username).join(', ') })}
        </Alert>
      </div>
    {/if}
    <div class="cols">
      <div class="col">
        <TokensTable rows={data.rows} {revoking} onrevoke={askRevoke} />
        <AgentAuditPanel entries={data.audit} {data} />
      </div>
      <div class="col">
        <McpPanel mcp={data.mcp} />
        <div id="tok-new">
          <TokenCreatePanel busy={creating} locked={created !== null} onsubmit={create} />
        </div>
      </div>
    </div>
  {:else if failure}
    <StateView kind="error" message={failure} onRetry={() => (attempt += 1)} />
  {:else}
    <SkeletonPage variant="compact" />
  {/if}

  <ConfirmDialog
    bind:open={broadOpen}
    danger={false}
    busy={creating}
    title={t('admin.tok.broad.title')}
    message={t('admin.tok.broad.body')}
    confirmLabel={t('admin.tok.broad.confirm')}
    onconfirm={() => answerBroad(true)}
    oncancel={() => answerBroad(false)}
  />
  <ConfirmDialog
    bind:open={revokeOpen}
    busy={revokeTarget ? revoking[revokeTarget.token.id] : false}
    title={t('admin.tok.revoke.title', { name: revokeTarget?.token.name ?? '' })}
    message={t('admin.tok.revoke.body', { user: revokeTarget?.owner.username ?? '' })}
    confirmLabel={t('admin.tok.revoke')}
    onconfirm={() => void revoke()}
  />
{/if}

<style>
  .msg {
    margin-bottom: 14px;
  }

  .cols {
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    align-items: start;
    gap: 16px;
  }

  .col {
    display: grid;
    gap: 16px;
    min-width: 0;
  }

  @media (min-width: 1600px) {
    .cols {
      grid-template-columns: minmax(0, 1fr) 380px;
    }
  }
</style>
