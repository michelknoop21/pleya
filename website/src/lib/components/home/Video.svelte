<script lang="ts">
  import AppleIcon from '~icons/simple-icons/apple';
</script>

<section class="video" id="video" aria-labelledby="video-title">
  <div class="wrap">
    <p class="kicker">Two and a half minutes</p>
    <h2 class="big video-title" id="video-title" data-reveal><span>Big <span class="video-title-p">P</span> shows you around.</span></h2>
    <p class="lede">
      The real app on Apple TV and iPhone, with Blender open movies on two demo servers. Requests, Tautulli and Pleya
      Share are drawn, because the demo servers do not run them.
    </p>
    <figure class="video-frame" data-reveal>
      <div class="video-stage">
        <div class="video-floor" aria-hidden="true"></div>
        <svg class="television-cable" viewBox="0 0 1200 160" fill="none" aria-hidden="true">
          <path d="M930 12 C960 40 926 69 932 99 C938 129 1006 129 1006 88" stroke="#090909" stroke-width="8" />
          <path d="M930 12 C960 40 926 69 932 99 C938 129 1006 129 1006 88" stroke="#454545" stroke-width="2" />
        </svg>
        <div class="television">
          <div class="television-bezel">
            <!-- svelte-ignore a11y_media_has_caption -->
            <video controls preload="none" playsinline width="1920" height="1080"
              poster="/video/pleya-with-big-p.jpg" aria-label="Pleya explained by Big P, with burned-in English subtitles">
              <source src="/video/pleya-with-big-p.mp4" type="video/mp4" />
            </video>
          </div>
          <div class="television-chin" aria-hidden="true"><span></span></div>
          <div class="television-feet" aria-hidden="true"><span></span><span></span></div>
        </div>
        <div class="apple-tv-device" aria-hidden="true">
          <svg class="apple-tv-body" viewBox="0 0 180 112" fill="none">
            <defs>
              <linearGradient id="apple-tv-top" x1="28" y1="5" x2="148" y2="87" gradientUnits="userSpaceOnUse">
                <stop stop-color="#424244" /><stop offset="0.45" stop-color="#28282b" /><stop offset="1" stop-color="#171719" />
              </linearGradient>
              <linearGradient id="apple-tv-front" x1="8" y1="82" x2="172" y2="106" gradientUnits="userSpaceOnUse">
                <stop stop-color="#27272a" /><stop offset="0.55" stop-color="#171719" /><stop offset="1" stop-color="#0c0c0e" />
              </linearGradient>
            </defs>
            <path d="M8 72 H172 V95 C172 106 162 110 151 110 H29 C18 110 8 106 8 95 Z" fill="url(#apple-tv-front)" />
            <path d="M38 4 H142 C154 4 161 8 164 18 L176 70 C179 83 168 89 154 89 H26 C12 89 1 83 4 70 L16 18 C19 8 26 4 38 4Z" fill="url(#apple-tv-top)" />
            <path d="M38 4.5 H142 C154 4.5 160 8 163 18" stroke="#67676b" stroke-opacity="0.65" />
            <path d="M7 80 C12 87 20 89 30 89 H150 C160 89 168 87 173 80" stroke="#555559" stroke-opacity="0.45" />
            <path d="M24 107 H155" stroke="#56565a" stroke-opacity="0.2" />
            <circle cx="154" cy="98" r="1.7" fill="#f4f1ec" />
          </svg>
          <div class="apple-tv-mark"><AppleIcon /><span>tv</span></div>
        </div>
      </div>
      <figcaption class="cap">English voice-over with burned-in subtitles. 2:38.</figcaption>
    </figure>
  </div>
</section>
