// Mockup 39: gedeelde stukken. De home-achtergrond volgt de iOS-app op main (Verify-screenshot
// ios.home), met Blender-posters in plaats van de effen fixtureblokken.
const P = '../detail-2026/';
const POSE = '../../../../assets/branding/bigp/';
// Volledige stilstaande poses (met armen); de app-assets missen de losse zwaai-arm.
const STILL = '../../tvos-unified/src/assets/bigp/';
const I = {
  search: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.4" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="6.5"/><path d="m20 20-4.8-4.8"/></svg>',
  home: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M3 11 12 3l9 8v10h-6v-6H9v6H3z"/></svg>',
  tv: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="7" width="18" height="13" rx="2"/><path d="m8 3 4 4 4-4"/></svg>',
  film: '<svg class="ic" viewBox="0 0 24 24" fill="currentColor"><path d="M3 9h18v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1zM3 5l3-1 1 4H3zM8 3.5l3.5-.8 1.2 5.3H8.8zM14 2.3l3.5-.8 1.6 6.5h-3.8z"/></svg>',
  mic: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><rect x="9" y="3" width="6" height="12" rx="3"/><path d="M5 11a7 7 0 0 0 14 0M12 18v3"/></svg>',
  follow: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><path d="M5 4v7a4 4 0 0 0 4 4h10"/><path d="m15 11 4 4-4 4"/></svg>',
  up: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 19V5M5 12l7-7 7 7"/></svg>',
  chev: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="m9 6 6 6-6 6"/></svg>',
  gear: '<svg class="ic" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M4.9 4.9l2.1 2.1M17 17l2.1 2.1M4.9 19.1 7 17M17 7l2.1-2.1"/></svg>',
};

const face = (pip = false, out = false) => `<span class="face ${out ? 'out' : ''}"><img src="${POSE}body.png">${pip ? '<span class="pip"></span>' : ''}</span>`;

function homeBg({ pip = false, out = false } = {}) {
  return `
  <div class="status"><span>9:41</span><div class="island"></div><span style="font-size:14px">100%</span></div>
  <div class="hdr"><img class="logo" src="../../../../assets/branding/pleya_wordmark.png"><span class="search">${I.search}</span>${face(pip, out)}<span class="mono ava">M</span></div>
  <div class="chips"><span>Series</span><span>Films</span></div>
  <div class="sec" style="top:186px">Verder kijken</div>
  <div class="land" style="top:228px"><div><img src="${P}sintel-wide.jpg"><b>Sintel</b></div><div><img src="${P}bbb-wide.jpg"><b>Big Buck Bunny</b></div></div>
  <div class="sec" style="top:432px">Recent toegevoegde films</div>
  <div class="rail" style="top:474px"><div><img src="${P}tears-poster.jpg"><b>Tears of Steel</b><i>2012</i></div><div><img src="${P}spring-poster.jpg"><b>Spring</b><i>2019</i></div><div><img src="${P}elephants-poster.jpg"><b>Elephants Dream</b></div></div>`;
}

function tabbar() {
  return `<div class="tabbar"><div class="on">${I.home}Home</div><div>${I.tv}Series</div><div>${I.film}Films</div><div><span class="mono tava">M</span>Mijn Pleya</div></div><div class="homeind"></div>`;
}

function keyboard({ dictating = false, sug = ['films', 'vanavond', 'series'] } = {}) {
  const row = (s) => `<div class="row">${[...s].map((c) => `<span class="k">${c}</span>`).join('')}</div>`;
  return `<div class="kb">
    <div class="sug">${sug.map((s) => `<span>${s}</span>`).join('')}</div>
    ${row('qwertyuiop')}${row('asdfghjkl')}
    <div class="row"><span class="k w">⇧</span>${[...'zxcvbnm'].map((c) => `<span class="k">${c}</span>`).join('')}<span class="k w">⌫</span></div>
    <div class="row"><span class="k w">123</span><span class="k w">🌐</span><span class="k w mic ${dictating ? 'on' : ''}" style="color:#fff">${I.mic.replace('class="ic"', 'class="ic" style="font-size:20px"')}</span><span class="k sp"></span><span class="k ret">Vraag</span></div>
  </div>`;
}

function bp(pose, { left, top, width, flip = false }) {
  return `<div class="bp" style="left:${left}px;top:${top}px;width:${width}px;${flip ? 'transform:scaleX(-1)' : ''}"><span class="shadow"></span><img src="${pose.startsWith('bigp-') ? STILL : POSE}${pose}.png"></div>`;
}

// Staart: een gedraaid vierkant dat half onder de ballonrand uitsteekt; (x,y) is de punt.
function tail(x, y, dir = 'down') {
  const rot = { down: 45, right: -45, left: 135, up: 225 }[dir];
  const off = { down: [-11, -26], right: [-26, -11], left: [4, -11], up: [-11, 4] }[dir];
  return `<span class="tail" style="left:${x + off[0]}px;top:${y + off[1]}px;transform:rotate(${rot}deg)"></span>`;
}

// Titelkaart. st: ['ok'|'req'|'ask', label]
const mc = (img, title, year, kind, st, { rank = null } = {}) => `
  <div class="mc"><div class="art"><img src="${P}${img}">${rank ? `<span class="rank">${rank}</span>` : ''}</div>
    <div class="txt"><div class="t">${title} <span>(${year})</span></div><div class="k">${kind}</div><span class="st ${st[0]}">${st[1]}</span></div>
    <span class="go">${I.chev}</span></div>`;

const fu = (qs) => `<div class="fu">${qs.map((q) => `<span class="pill">${I.follow}${q}</span>`).join('')}</div>`;
const wave = (n = 14) => `<span class="wave">${Array.from({ length: n }, (_, i) => `<i style="height:${4 + Math.round(Math.abs(Math.sin(i * 1.7)) * 15)}px"></i>`).join('')}</span>`;
