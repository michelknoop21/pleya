<!--
  Versie, audio en ondertitels van een film als drie keuzelijsten naast elkaar.

  De lijsten tonen wat `Version` draagt, met dezelfde kenmerken per spoor als
  VersionPanel. De keuze reist als stream-id mee naar de speler (`?audio=` en
  `?subtitle=`) en geldt dan voor die ene afspeelactie. Met
  `capabilities.track_preferences` wordt ze ook bij het item bewaard. Die
  voorkeur is een taal en geen spoor: een spoor zonder taalcode van twee of drie
  letters is niet te bewaren en geldt dan alleen voor de eerstvolgende actie.
-->
<script lang="ts">
  import { untrack } from 'svelte';
  import { describeError } from '../api/errors';
  import { personalApi } from '../api/personal';
  import type { Item, Version } from '../api/types';
  import { t } from '../i18n';
  import type { TrackPick } from '../player/route';
  import { isBrowserSubtitle } from '../player/tracks';
  import { session } from '../stores/session.svelte.js';
  import { formatLanguage } from '../util/format';
  import Select, { type SelectOption } from './Select.svelte';

  interface Props {
    item: Pick<Item, 'id'>;
    version: Version | undefined;
    versionOptions: SelectOption[];
    onversion: (id: string) => void;
    /** De sporen voor de spelerlink; leeg zolang de standaard van het bestand geldt. */
    onpick: (tracks: TrackPick) => void;
  }
  type Preference = Awaited<ReturnType<ReturnType<typeof personalApi>['trackPreference']>>;

  let { item, version, versionOptions, onversion, onpick }: Props = $props();

  const LANGUAGE = /^[a-zA-Z]{2,3}$/;
  let preference = $state<Preference | null>(null);
  let picked = $state<TrackPick>({});
  let error = $state<string | null>(null);

  const remembers = $derived(session.capabilities?.track_preferences === true);
  // Een audiokeuze die niets kan uitvoeren blijft weg: de server plant het spoor, of de browser wisselt zelf.
  const canAudio = $derived(
    session.capabilities?.playback_audio_selection === true ||
    (typeof HTMLMediaElement !== 'undefined' && 'audioTracks' in HTMLMediaElement.prototype)
  );
  const audios = $derived(version?.audio_streams ?? []);
  const subtitles = $derived(version?.subtitle_streams ?? []);
  const sameLanguage = (a?: string | null, b?: string | null) => !!a && !!b && a.toLowerCase() === b.toLowerCase();
  const named = (parts: (string | null | undefined)[], index: number) =>
    parts.filter(Boolean).join(' · ') || t('player.trackUnnamed', { index: index + 1 });

  const defaultAudio = $derived(audios.find(stream => stream.is_default)?.id ?? audios[0]?.id ?? '');
  const audioId = $derived(
    picked.audio ?? audios.find(stream => sameLanguage(stream.language, preference?.audio_language))?.id ?? defaultAudio
  );
  const preferredSubtitle = $derived.by(() => {
    const mode = preference?.subtitle_mode;
    if (!mode || mode === 'off') return '';
    const matches = subtitles.filter(stream => sameLanguage(stream.language, preference?.subtitle_language));
    return (matches.find(stream => stream.is_forced === (mode === 'forced')) ?? matches[0])?.id ?? '';
  });
  const subtitleId = $derived(picked.subtitle ?? preferredSubtitle);
  const chosenSubtitle = $derived(subtitles.find(stream => stream.id === subtitleId));

  const audioOptions = $derived(audios.map((stream, index) => ({
    value: stream.id,
    label: named([formatLanguage(stream.language), stream.codec, stream.channels ? `${stream.channels}ch` : null, stream.title, stream.is_default ? t('item.default') : null], index)
  })));
  const subtitleOptions = $derived([
    { value: '', label: t('player.subtitlesOff') },
    ...subtitles.map((stream, index) => ({
      value: stream.id,
      label: named([formatLanguage(stream.language), stream.format, stream.is_forced ? t('item.forced') : null, stream.is_hearing_impaired ? t('item.sdh') : null, stream.is_external ? t('item.external') : null], index)
    }))
  ]);

  // De bewaarde voorkeur kiest alleen de beginstand; een fout laat de standaard van het bestand staan.
  $effect(() => {
    const id = item.id;
    if (!remembers) return;
    const controller = new AbortController();
    personalApi(session.client).trackPreference(id, controller.signal)
      .then(loaded => { if (!controller.signal.aborted) preference = loaded; })
      .catch(() => undefined);
    return () => controller.abort();
  });

  // Het standaardspoor gaat niet mee: de speler kiest dat zelf, en een expliciete audiokeuze sluit direct play uit.
  $effect(() => {
    const tracks: TrackPick = {
      ...(canAudio && audioId && audioId !== defaultAudio ? { audio: audioId } : {}),
      ...(subtitleId ? { subtitle: subtitleId } : {})
    };
    untrack(() => onpick(tracks));
  });

  async function save(body: Parameters<ReturnType<typeof personalApi>['setTrackPreference']>[1]): Promise<void> {
    if (!remembers || Object.keys(body).length === 0) return;
    error = null;
    try {
      preference = await personalApi(session.client).setTrackPreference(item.id, body);
    } catch (err) {
      error = describeError(err);
    }
  }
  const language = (code?: string | null) => (code && LANGUAGE.test(code) ? code : null);

  function pickAudio(id: string): void {
    picked = { ...picked, audio: id };
    const code = language(audios.find(stream => stream.id === id)?.language);
    if (code) void save({ audio_language: code });
  }
  function pickSubtitle(id: string): void {
    picked = { ...picked, subtitle: id };
    const stream = subtitles.find(candidate => candidate.id === id);
    if (!stream) return void save({ subtitle_mode: 'off' });
    const code = language(stream.language);
    // Zonder taalcode zegt "aan" niets over welk spoor; dan wordt er niets bewaard.
    if (code) void save({ subtitle_language: code, subtitle_mode: stream.is_forced ? 'forced' : 'on' });
  }
</script>

<div class="tracks">
  <div class="tracks__lists">
    {#if versionOptions.length > 0}
      <Select label={t('item.version')} value={version?.id ?? ''} options={versionOptions} onchange={value => { picked = {}; onversion(value); }} />
    {/if}
    {#if canAudio && audioOptions.length > 0}
      <Select label={t('item.audio')} value={audioId} options={audioOptions} onchange={pickAudio} />
    {/if}
    {#if subtitles.length > 0}
      <Select label={t('item.subtitles')} value={subtitleId} options={subtitleOptions} onchange={pickSubtitle} />
    {/if}
  </div>
  {#if (canAudio && audioOptions.length > 0) || subtitles.length > 0}
    <p class="tracks__note t-small">{t(remembers ? 'detail.tracks.remembered' : 'detail.tracks.once')}</p>
  {/if}
  {#if chosenSubtitle && !isBrowserSubtitle(chosenSubtitle, session.capabilities?.embedded_subtitles === true)}
    <p class="tracks__note t-small">{t('detail.tracks.notInBrowser')}</p>
  {/if}
  {#if error}<p class="tracks__note t-small" role="alert">{error}</p>{/if}
</div>

<style>
  .tracks { display: flex; flex-direction: column; gap: var(--space-half); margin-top: var(--space-half); min-width: 0; }
  /* Drie naast elkaar waar het past; op een telefoon onder elkaar. */
  .tracks__lists { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 180px), 1fr)); gap: var(--space); }
  .tracks__lists :global(select) { text-overflow: ellipsis; }
  .tracks__note { margin: 0; color: var(--ink-2); }
</style>
