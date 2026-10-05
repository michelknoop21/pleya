<script lang="ts">
  import wordmark from '$lib/assets/pleya_wordmark.png';
  import { SOURCE_REPO_URL } from '$lib/config';
  const year = new Date().getFullYear();
</script>

<footer class="site-footer" id="footer">
  <div class="footer-inner">
    <div class="footer-content">
      <a class="footer-brand" href="/" aria-label="Pleya home"><img src={wordmark} width="1516" height="659" alt="Pleya" /></a>
    <nav class="footer-nav" aria-label="Footer">
      <div class="footer-group"><h3>Watch</h3>
        <a href="/iphone">iPhone</a>
        <a href="/apple-tv">Apple TV</a>
        <a href="/mac">Mac</a>
      </div>
      <div class="footer-group"><h3>Explore</h3>
        <a href="/docs">Guide</a>
        <a href="/releases">Release notes</a>
      </div>
      <div class="footer-group"><h3>Project</h3>
        <a href="/privacy">Privacy Policy</a>
        <a href={SOURCE_REPO_URL} target="_blank" rel="noopener noreferrer">Source</a>
        <a href="/LICENSE.txt">License</a>
        <a href="/NOTICE.txt">Notices</a>
      </div>
    </nav>
    </div>
    <div class="footer-meta">
      <p>© {year} Michel Knoop</p>
      <p>Free software · <a href="/LICENSE.txt" target="_blank" rel="noopener noreferrer">GPL-3.0</a> · <a href="/media-credits.html">Media credits</a></p>
    </div>
  </div>
</footer>

<style>

.site-footer { --wrap: 78rem; --gutter: 1.25rem; padding: 3rem var(--gutter, 1.5rem) 2rem; border-top: 1px solid var(--color-border); }
.footer-inner { max-width: calc(var(--wrap, 64rem) - var(--gutter, 1.5rem) * 2); margin-inline: auto; }
.footer-content { display: grid; gap: 2.5rem; align-items: start; }
.footer-brand { display: inline-block; width: fit-content; }
.footer-brand img { display: block; width: 6.4rem; height: auto; }
.footer-nav { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); gap: 1rem; }
.footer-group { min-width: 0; }
.footer-group h3 { margin: 0 0 .65rem; font-family: var(--font-sans); font-size: .6875rem; line-height: 1.5; font-weight: 600; letter-spacing: .1em; text-transform: uppercase; color: var(--color-text-faint); }
.footer-group a { display: flex; align-items: center; width: fit-content; min-height: 44px; color: var(--color-text-muted); font-size: .875rem; line-height: 1.4; text-decoration: none; transition: color 150ms ease; }
.footer-group a:hover { color: var(--color-text); }
.footer-meta { display: grid; gap: .5rem; margin-top: 2rem; padding-top: 1.25rem; border-top: 1px solid var(--color-border); color: var(--color-text-faint); font-size: .8125rem; line-height: 1.6; }
.footer-meta p { margin: 0; }
.footer-meta a { color: var(--color-text-muted); text-decoration: underline; text-underline-offset: 3px; }
.footer-brand:focus-visible, .footer-nav a:focus-visible, .footer-meta a:focus-visible { outline: 2px solid var(--color-amber); outline-offset: 4px; border-radius: 3px; }
@media (min-width: 640px) {
 .site-footer { padding-block: 3.5rem 2rem; }
 .footer-content { grid-template-columns: minmax(0, 1fr) minmax(0, 1.5fr); gap: 3rem; }
 .footer-nav { gap: 2rem; }
 .footer-meta { grid-template-columns: minmax(0, 1fr) minmax(0, 1.5fr); gap: 3rem; }
}
@media (min-width: 768px) { .site-footer { --gutter: 2rem; } }
@media (min-width: 1000px) {
 .footer-content, .footer-meta { grid-template-columns: minmax(0, 1fr) minmax(0, 34rem); }
}
</style>
