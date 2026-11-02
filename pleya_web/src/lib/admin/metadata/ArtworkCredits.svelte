<script lang="ts">
  import { t } from '../../i18n';
</script>
<section class="credits" aria-label={t('admin.metadata.artwork.credits')}>
  <h3>{t('admin.metadata.artwork.credits')}</h3>
  <div class="credit-body">
    <a href="https://www.themoviedb.org" target="_blank" rel="noopener noreferrer"><img src="/providers/tmdb.svg" alt="TMDB" width="64" height="46" /></a>
    <p lang="en">{t('admin.metadata.artwork.creditNotice')}</p>
  </div>
</section>
<style>
  .credits { margin-top:18px; padding-top:14px; border-top:1px solid var(--hairline); }
  h3 { color:var(--ink-2); min-height:44px; display:block; align-content:center; font-size:13px; }
  .credit-body { display:flex; gap:18px; align-items:center; padding:4px 0 10px; }
  .credit-body a { flex:none; }
  .credit-body img { display:block; object-fit:contain; }
  .credit-body p { color:var(--ink-2); font-size:12px; line-height:1.5; max-width:55ch; margin:0; }
</style>
