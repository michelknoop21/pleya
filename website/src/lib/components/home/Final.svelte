<script lang="ts">
  import bigP from '$lib/assets/home/bigp-blij.png';
  import { cta } from '$lib/config';
</script>

<section class="final" data-reveal data-moment="goodbye">
  <div class="spill" aria-hidden="true"></div>
  <h2 class="wrap">Lights down.<br /><span class="grad">Library up.</span></h2>
  <p class="wrap">Private beta on iPhone, Apple TV and Mac.</p>
  <div class="actions">
    <a class="cta" href={cta.href}>{cta.label}</a>
    <p class="cta-note">{cta.note}</p>
  </div>
  <div class="final-peek-window" aria-hidden="true"><img src={bigP} alt="" /></div>
</section>
