<!--
  Annuleren en Opslaan onder een instellingenscherm (28, 30, 31), met de
  bevestiging die elke van die drie schermen vraagt: ze raken tokenbeleid,
  sessies of het netwerk. De dialoog noemt wat er verandert en wat het kan
  kosten; een wijziging die jezelf kan buitensluiten krijgt een eigen, zware
  waarschuwing.

  Een weigering van de server laat het formulier staan zoals het was: de
  pagina houdt haar concept, deze component toont alleen de melding. De server
  past een PATCH helemaal of niet toe (`settings.invalid_value` wijzigt niets).
-->
<script lang="ts">
  import { adminSettingsApi } from '../../api/adminSettings';
  import type { Settings, SettingsPatch } from '../../api/types';
  import Alert from '../../components/Alert.svelte';
  import ConfirmDialog from '../../components/ConfirmDialog.svelte';
  import { t } from '../../i18n';
  import { session } from '../../stores/session.svelte';
  import LibraryProblemAlert from '../LibraryProblemAlert.svelte';
  import type { LibraryProblem } from '../libraryErrors';
  import { settingsProblem } from './settingsErrors';
  import { isEmptyPatch, type Risk } from './settings';

  interface Props {
    patch: SettingsPatch;
    /** Invoer die de pagina zelf al afkeurt: Opslaan blijft dan uit. */
    blocked?: boolean;
    risks: Risk[];
    /** Eén regel per gewijzigde instelling, voor de bevestiging. */
    lines: string[];
    onsaved: (settings: Settings) => void;
    oncancel: () => void;
    /** Alleen voor tests: een eigen opslagfunctie in plaats van de echte client. */
    save?: (patch: SettingsPatch) => Promise<Settings>;
  }

  let { patch, blocked = false, risks, lines, onsaved, oncancel, save }: Props = $props();

  let open = $state(false);
  let busy = $state(false);
  let problem = $state<LibraryProblem | null>(null);
  let notice = $state(false);

  const dirty = $derived(!isEmptyPatch(patch));
  const lockout = $derived(risks.some((r) => r.lockout));

  async function apply(): Promise<void> {
    busy = true;
    problem = null;
    notice = false;
    try {
      const run = save ?? ((p: SettingsPatch) => adminSettingsApi(session.client).patchSettings(p));
      const result = await run(patch);
      open = false;
      notice = true;
      onsaved(result);
    } catch (err) {
      open = false;
      problem = settingsProblem(err);
    } finally {
      busy = false;
    }
  }
</script>

{#if notice}
  <div class="msg"><Alert tone="info">{t('admin.set.saved')}</Alert></div>
{/if}
{#if problem}
  <div class="msg">
    <LibraryProblemAlert {problem} onretry={() => (open = true)} onreload={() => location.reload()} />
  </div>
{/if}

<div class="bar">
  <button
    type="button"
    class="btn btn--secondary"
    disabled={!dirty || busy}
    onclick={() => {
      problem = null;
      notice = false;
      oncancel();
    }}
  >
    {t('admin.set.action.cancel')}
  </button>
  <button
    type="button"
    class="btn"
    disabled={!dirty || blocked || busy}
    onclick={() => {
      problem = null;
      notice = false;
      open = true;
    }}
  >
    {t('admin.set.action.save')}
  </button>
</div>

<ConfirmDialog
  bind:open
  {busy}
  danger={lockout}
  title={t('admin.set.confirm.title')}
  message={t('admin.set.confirm.intro')}
  confirmLabel={t('admin.set.action.save')}
  onconfirm={() => void apply()}
>
  <ul class="lines">
    {#each lines as line (line)}<li>{line}</li>{/each}
  </ul>
  {#each risks as risk (risk.key)}
    <p class="risk" class:risk--lockout={risk.lockout}>
      {#if risk.lockout}<strong>{t('admin.set.confirm.lockout')}</strong>{/if}
      {t(risk.key, risk.params)}
    </p>
  {/each}
</ConfirmDialog>

<style>
  .msg {
    margin-top: 16px;
  }

  .bar {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 10px;
    margin-top: 18px;
  }

  .lines {
    margin: 0 0 10px;
    padding-left: 18px;
    font-size: 13.5px;
    color: var(--ink-2);
    overflow-wrap: anywhere;
  }

  .risk {
    margin: 8px 0 0;
    font-size: 13px;
    line-height: 1.45;
    color: var(--ink-2);
  }

  .risk--lockout {
    color: var(--danger-ink);
  }

  @media (max-width: 599px) {
    .bar {
      flex-direction: column-reverse;
    }
  }
</style>
