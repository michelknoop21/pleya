<script lang="ts">
  import MicIcon from '~icons/material-symbols-light/mic-outline-rounded';
  import SearchIcon from '~icons/material-symbols-light/search-rounded';
  import ForumIcon from '~icons/material-symbols-light/forum-outline-rounded';

  // The questions are the app's own examples (assistant.idle.examples, mobile.examples and
  // followUp in lib/i18n/en.i18n.json); the label says what Big P does with each.
  const asks = [
    { q: 'Who watched the most this week?', does: 'Watch statistics per person' },
    { q: 'Who is watching right now?', does: 'Live activity on your servers' },
    { q: 'Which films are missing between my servers?', does: 'Compares two servers title by title' },
    { q: "Which popular new movies don't I have yet?", does: 'What is trending, minus your library' },
    { q: 'Which movies have sat unwatched in my library for a long time?', does: 'Your own watch history' },
    { q: 'What was added this week?', does: 'New arrivals across servers' },
    { q: 'Which tasks failed on my servers today? Restart them.', does: 'Server jobs, with a status per job' },
    { q: 'Scan all movie libraries on all my servers.', does: 'One sentence, every server' },
  ];
</script>

<section class="bp-section more" id="more" aria-labelledby="more-title">
  <div class="wrap">
    <div class="bp-head" data-reveal>
      <p class="eyebrow">How you ask</p>
      <h2 id="more-title" data-split>Say it, or type it.</h2>
    </div>

    <ul class="ways" data-reveal>
      <li><SearchIcon aria-hidden="true" /><h3>Call him where you are</h3><p>From Home, from Search, or from the menu of a title with Ask Big P. He opens next to what you were doing.</p></li>
      <li><MicIcon aria-hidden="true" /><h3>Speak or type</h3><p>Dictate the question or type it. Big P can answer with a short spoken reaction, never while you dictate or watch.</p></li>
      <li><ForumIcon aria-hidden="true" /><h3>Ask more</h3><p>A follow-up continues the same conversation, and Big P suggests questions to ask next.</p></li>
    </ul>

    <h3 class="sub" data-reveal><span>More from the app's own examples</span></h3>
    <ul class="asks" data-reveal>
      {#each asks as a (a.q)}
        <li><q>{a.q}</q><span>{a.does}</span></li>
      {/each}
    </ul>
    <p class="aside">
      He can also turn a search into a row on your home screen or into a collection, add the age rating and where a
      title streams when you switch on online information, and say whether what you are playing is transcoding and why.
    </p>
  </div>
</section>

<style>
  .ways { margin-top: 3rem; display: grid; gap: 2rem; }
  .ways :global(svg) { font-size: 2rem; color: var(--amber); }
  .ways h3 { margin-top: 0.7rem; font-family: var(--display); font-size: 1.45rem; letter-spacing: -0.02em; }
  .ways p { margin-top: 0.4rem; max-width: 24rem; color: var(--muted); font-size: 0.98rem; line-height: 1.55; }
  .sub { margin-top: 4.5rem; color: var(--amber); font-family: var(--font-sans); font-size: 0.74rem; font-weight: 600; letter-spacing: 0.12em; text-transform: uppercase; }
  .asks { margin-top: 1rem; display: grid; }
  .asks li { display: grid; align-content: start; gap: 0.25rem; padding-block: 1.1rem; border-top: 1px solid var(--hair); }
  .asks q { quotes: none; font-family: var(--display); font-size: clamp(1.2rem, 2vw, 1.6rem); font-weight: 600; line-height: 1.2; letter-spacing: -0.02em; }
  .asks span { color: var(--muted); font-size: 0.92rem; }
  .aside { margin-top: 2rem; max-width: 44rem; color: var(--muted); }
  @media (min-width: 800px) {
    .ways { grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 3rem; }
    .asks { grid-template-columns: repeat(2, minmax(0, 1fr)); column-gap: 4rem; }
  }
</style>
