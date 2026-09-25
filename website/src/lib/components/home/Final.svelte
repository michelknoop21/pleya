<script lang="ts">
  import { cta } from '$lib/config';
</script>

<section class="final" data-reveal>
  <div class="spill" aria-hidden="true"></div>
  <h2 class="wrap">Lights down.<br /><span class="grad">Library up.</span></h2>
  <p class="wrap">Private beta on iPhone, Apple TV and Mac.</p>
  <div class="actions">
    <a class="cta" href={cta.href}>{cta.label}</a>
    <p class="cta-note">{cta.note}</p>
  </div>
</section>
