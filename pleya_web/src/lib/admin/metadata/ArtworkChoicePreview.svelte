<script lang="ts">
  import { untrack } from 'svelte';
  import type { ArtworkCandidate } from '../../api/types';
  import { adminSettingsApi } from '../../api/adminSettings';
  import Artwork from '../../components/Artwork.svelte';
  import { setArtworkLoader } from '../../components/artworkLoader';
  import { session } from '../../stores/session.svelte';
  import { t } from '../../i18n';

  let { itemId, candidate }: { itemId: string; candidate: ArtworkCandidate } = $props();
  const own = untrack(() => ({itemId, candidate, client:session.client, generation:session.client.sessionGeneration, subject:session.me?.id}));
  setArtworkLoader(async (_id, signal, width) => {
    const current=()=>!signal.aborted && session.client===own.client && own.client.sessionGeneration===own.generation && session.me?.id===own.subject && session.canAdminister===true && session.capabilities?.artwork_choices===true;
    if(!current()) throw new Error('artwork preview context changed');
    const value=own.candidate;
    const blob=value.artwork_id ? await own.client.artworkBlob(value.artwork_id,signal,width)
      : value.source==='tmdb' && value.preview_ref && (value.role==='poster'||value.role==='backdrop')
        ? await adminSettingsApi(own.client).metadataCandidateArtwork(own.itemId,value.preview_ref,value.role,signal)
        : null;
    if(!blob || !current()) throw new Error('artwork preview unavailable');
    return blob;
  });
</script>
<Artwork artworkId={candidate.id} alt={t('admin.metadata.artwork.preview',{role:t(candidate.role==='poster'?'admin.metadata.artwork.poster':'admin.metadata.artwork.backdrop')})} shape={candidate.role==='poster'?'poster':'wide'} eager />
