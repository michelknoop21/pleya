<script lang="ts">
 import Wordmark from '#lib/components/Wordmark.svelte';
 import Steps from '#lib/components/Steps.svelte';
 import SetupOwner from '#lib/setup/SetupOwner.svelte';
 import SetupWizard from '#lib/setup/SetupWizard.svelte';
 import StateView from '#lib/components/StateView.svelte';
 import { session } from '#lib/stores/session.svelte.js';
 import { t } from '#lib/i18n/index.js';
 let step = $state(0);
 const allowed = $derived(session.phase === 'setup' || session.canAdminister);
</script>
<svelte:head><title>{t('setup.title')} · Pleya</title></svelte:head>
{#if allowed}
 <div class="setup"><div class="box">
  <div class="brand"><Wordmark size="form" /></div>
  <Steps steps={[t('setup.ownerStep'),t('setup.storageStep'),t('setup.libraryStep'),t('setup.scanStep')]} current={session.phase === 'setup' ? 0 : step} />
  {#if session.phase === 'setup'}<SetupOwner />{:else}<SetupWizard onstep={(next) => step=next} />{/if}
 </div></div>
{:else}<StateView kind="empty" title="404" message={t('setup.notAllowed')} />{/if}
<style>
.setup{display:flex;justify-content:center;align-items:flex-start;padding:60px 24px;min-height:100vh}.box{width:100%;max-width:620px;min-width:0}.brand{height:36px;margin-bottom:26px}@media(max-width:899px){.setup{padding:24px 16px 40px}}
</style>
