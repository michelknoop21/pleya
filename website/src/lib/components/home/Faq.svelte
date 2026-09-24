<script lang="ts">
  import { faqs } from '$lib/content/faqs';
</script>

<section class="faq" id="faq">
  <div class="wrap">
    <p class="kicker">Before you join</p>
    <div class="faq-list">
      {#each faqs as faq, i (faq.id)}
        <details open={i === 0}>
          <summary>{faq.question}</summary>
          <p>{faq.answer}</p>
        </details>
      {/each}
    </div>
  </div>
</section>
