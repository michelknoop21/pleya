<!--
  "Cast en crew" op het filmdetail: naam en rol uit `Item.people`, met initialen
  in een cirkel. Een persoon is in het contract een naam met een rol en heeft
  geen eigen identiteit, dus er is geen foto en geen link naar een
  persoonspagina. Zonder personen verschijnt de sectie niet.
-->
<script lang="ts">
  import type { Item } from '../api/types';
  import { t } from '../i18n';

  let { people }: { people: Item['people'] } = $props();

  const ROLES = ['director', 'actor', 'writer'] as const;
  // Regie eerst, dan de acteurs, dan het scenario; een onbekende rol valt weg (contract).
  const shown = $derived(ROLES.flatMap(role =>
    (people ?? []).filter(person => person.role === role && person.name.trim())
  ));
  const initials = (name: string) => {
    const words = name.trim().split(/\s+/);
    return [words[0], words.length > 1 ? words[words.length - 1] : '']
      .map(word => [...(word ?? '')][0] ?? '').join('').toUpperCase();
  };
  const roleLabel = (person: (typeof shown)[number]) =>
    person.role === 'actor' ? person.character?.trim() || t('detail.actor') : t(`item.${person.role}`);
</script>

{#if shown.length > 0}
  <section class="cast" aria-labelledby="cast-crew">
    <h2 class="cast__h" id="cast-crew">{t('detail.castCrew')}</h2>
    <ul class="cast__list">
      {#each shown as person, index (index)}
        <li class="cast__person">
          <span class="cast__initials" aria-hidden="true">{initials(person.name)}</span>
          <span class="cast__text"><span class="cast__name">{person.name}</span><span class="cast__role">{roleLabel(person)}</span></span>
        </li>
      {/each}
    </ul>
  </section>
{/if}

<style>
  .cast { display: flex; flex-direction: column; gap: var(--space); min-width: 0; }
  .cast__h { margin: 0; font-size: 20px; font-weight: 700; letter-spacing: -0.01em; color: var(--ink); }
  .cast__list { display: grid; grid-template-columns: repeat(auto-fill, minmax(min(100%, 200px), 1fr)); gap: var(--space); list-style: none; margin: 0; padding: 0; }
  .cast__person { display: flex; align-items: center; gap: 12px; min-width: 0; }
  .cast__initials { display: grid; place-items: center; flex: none; width: 48px; height: 48px; border-radius: 999px; background: var(--elevated); color: var(--ink-2); font-size: 15px; font-weight: 700; }
  .cast__text { display: flex; flex-direction: column; min-width: 0; }
  .cast__name, .cast__role { overflow-wrap: anywhere; }
  .cast__role { color: var(--ink-2); font-size: 13px; }
  @media (max-width: 899px) { .cast__h { font-size: 18px; } }
</style>
