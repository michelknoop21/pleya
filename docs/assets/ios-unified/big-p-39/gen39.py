import pathlib, sys
D = pathlib.Path(__file__).resolve().parent
PAGES = {}

def page(name, title, js, size=(402, 874)):
    PAGES[name] = (title, js, size)

page('39-a-gezichtsknop', '39 A Gezichtsknop', 'document.body.innerHTML = homeBg() + tabbar();')

page('39-b-opgeroepen', '39 B Opgeroepen', r'''document.body.innerHTML = homeBg({out:true}) + tabbar() + `<div class="dim"></div>
<div class="ball" style="left:12px;right:12px;top:96px">
  <div class="greet">Hoi Michel, wat zoeken we?</div>
  <div class="pills"><span class="pill">Wat kan ik vanavond kijken?</span><span class="pill">Welke films heb ik nog niet gezien?</span><span class="pill">Wie heeft deze week het meest gekeken?</span></div>
</div>` + tail(318, 324) + bp('bigp-zwaaien', {left:214, top:314, width:190}) +
`<div class="input" style="top:520px"><span class="txt ph"><span class="caret"></span> Vraag Big P</span><span class="send off">${I.up}</span></div>` + keyboard();''')

page('39-c-geen-model', '39 C Eerste keer zonder model', r"""document.body.innerHTML = homeBg({out:true}) + tabbar() + `<div class="dim"></div>
<div class="ball" style="left:12px;right:12px;top:318px">
  <div class="state"><span class="dot busy"></span>Nog niet ingesteld</div>
  <div class="greet" style="margin-top:10px">Ik heb nog geen brein.</div>
  <div class="label" style="margin-top:8px;font-size:15px;line-height:1.4">Kies een taalmodel, dan zoek ik films, vraag ik titels aan en regel ik je servers.</div>
  <div class="pills" style="margin-top:16px"><span class="pill pri">${I.gear}Model instellen</span></div>
  <div class="label" style="font-size:13px;margin-top:14px">Je instelling gaat via je iCloud-sleutelhanger mee naar je iPad en Apple TV.</div>
</div>` + tail(312, 582) + bp('bigp-verrast', {left:204, top:562, width:200});""")

page('39-d-dicteren', '39 D Dicteren', r"""document.body.innerHTML = homeBg({out:true}) + tabbar() + `<div class="dim"></div>
<div class="ball" style="left:12px;right:12px;top:250px">
  <div class="state"><span class="dot"></span>Ik luister…</div>
  <div class="label" style="margin-top:8px;font-size:15px">Spreek je vraag in, of typ hem.</div>
</div>` + tail(318, 340) + bp('bigp-blij', {left:214, top:314, width:190}) +
`<div class="input" style="top:520px"><span class="txt">welke animatiefilms heb ik nog niet ge<span class="caret"></span></span>${wave()}<span class="send">${I.up}</span></div>` + keyboard({dictating:true, sug:['gezien','gekeken','gedaan']});""")

page('39-e-antwoord-titels', '39 E Antwoord met titels', r"""document.body.innerHTML = homeBg({out:true}) + tabbar() + `<div class="dim"></div>
<div class="ball" style="left:12px;right:12px;top:100px">
  <div class="asked"><span>Je vroeg: </span>Welke animatiefilms heb ik nog niet gezien?</div>
  <div class="answer">Drie nog niet. Spring staat niet op je server, die kan ik aanvragen.</div>
  <div class="cards">
    ${mc('tears-poster.jpg','Tears of Steel',2012,'Film · 12 min',['ok','In je bibliotheek · NAS'])}
    ${mc('elephants-poster.jpg','Elephants Dream',2006,'Film · 11 min',['ok','In je bibliotheek · NAS'])}
    ${mc('spring-poster.jpg','Spring',2019,'Film · 8 min',['ask','Aan te vragen'])}
  </div>
</div>` + tail(326, 614) + bp('bigp-vinger_presenteren', {left:196, top:586, width:196}) +
`<div class="fu float" style="position:absolute;left:12px;top:626px;width:240px;flex-direction:column;z-index:29">
  <span class="pill">${I.follow}Wat kan ik vanavond kijken?</span><span class="pill">${I.follow}Wat is er net toegevoegd?</span><span class="pill">${I.follow}Wat staat op mijn lijst?</span></div>` +
`<div class="input" style="top:790px"><span class="txt ph">Vraag verder</span><span class="send off">${I.mic}</span></div><div class="homeind"></div>`;""")

page('39-f-kijkcijfers', '39 F Kijkcijfers', r"""document.body.innerHTML = homeBg({out:true}) + tabbar() + `<div class="dim"></div>
<div class="ball" style="left:12px;right:12px;top:58px">
  <div class="asked"><span>Je vroeg: </span>Wie heeft deze week het meest gekeken?</div>
  <div class="answer">Robin keek het meest, vooral Sintel.</div>
  <div class="wc"><div class="top"><div><h4>Kijkcijfers</h4><div class="sub">NAS · Afgelopen 7 dagen</div></div><div class="tot"><b>83</b><span>keer gekeken</span></div></div>
    <div class="vs">
      <div class="v lead"><span class="mono" style="background:#6b2f6e">R</span><b>Robin</b><i>36×</i></div>
      <div class="v"><span class="mono" style="background:#2f4f8a">M</span><b>Michel</b><i>19×</i></div>
      <div class="v"><span class="mono" style="background:#2f6e52">S</span><b>Sam</b><i>17×</i></div>
      <div class="v"><span class="mono" style="background:#7a5a20">N</span><b>Noor</b><i>8×</i></div>
      <div class="v"><span class="mono" style="background:#5a6b2f">J</span><b>Jan</b><i>3×</i></div>
    </div></div>
  <div class="cards">
    ${mc('sintel-poster.jpg','Sintel',2010,'19× bekeken · Robin · Sam',['ok','In je bibliotheek · NAS'],{rank:1})}
    ${mc('caminandes-poster.jpg','Caminandes',2016,'9× bekeken · Noor',['ok','In je bibliotheek · NAS'],{rank:2})}
  </div>
</div>` + tail(326, 627) + bp('bigp-duim_presenteren', {left:222, top:597, width:180}) +
`<div class="fu float" style="position:absolute;left:12px;top:650px;width:220px;flex-direction:column;z-index:29">
  <span class="pill">${I.follow}En deze maand?</span><span class="pill">${I.follow}En vandaag?</span><span class="pill">${I.follow}Wie kijkt er nu?</span></div>` +
`<div class="input" style="top:790px"><span class="txt ph">Vraag verder</span><span class="send off">${I.mic}</span></div><div class="homeind"></div>`;""")

page('39-g-bevestigen', '39 G Bevestigen', r"""document.body.innerHTML = homeBg({out:true}) + tabbar() + `<div class="dim"></div>
<div class="ball cf" style="left:12px;right:12px;top:118px">
  <div class="asked"><span>Je vroeg: </span>Maak Sam aan en geef hem alleen Kids.</div>
  <h3>Gebruiker aanmaken op NAS?</h3>
  <div class="rows"><div><span>Naam</span><b>Sam</b></div><div><span>Server</span><b>NAS · Pleya Server</b></div><div><span>Bibliotheken</span><b>Kids</b></div><div><span>Mag</span><b>Kijken</b></div></div>
  <div class="why">Pleya heeft dit voorstel zelf opgebouwd en gecontroleerd. Big P kan het niet voor je bevestigen.</div>
  <div class="btns"><span class="pill">Annuleren</span><span class="pill pri">Aanmaken</span></div>
</div>` + tail(320, 557) + bp('bigp-bezorgd', {left:214, top:566, width:190});""")

page('39-h-terug-naar-big-p', '39 H Na een tik op een titel', r"""document.body.innerHTML = `<iframe src="../detail-2026/D-01-film.html" style="position:absolute;inset:0;width:402px;height:874px;border:0" scrolling="no"></iframe>
<div class="peek" style="left:322px;top:792px;width:80px;height:82px"><img src="${STILL}bigp-zwaaien.png" style="width:170px;left:-30px;top:-12px;transform:rotate(-14deg)"></div>
<div class="peek-tip" style="right:74px;top:812px"><span class="pill" style="background:rgba(31,35,35,.97);border:1px solid var(--panel-line);font-size:14px;min-height:36px">${I.follow}Nog 2 titels</span></div>`;""")

page('39-i-ipad', '39 I iPad', r"""document.body.innerHTML = `<div style="position:absolute;inset:0;zoom:1">
  <div class="status" style="padding:6px 28px 0 28px"><span style="font-size:15px">9:41  di 3 okt</span><span style="font-size:14px">100%</span></div>
  <div class="hdr" style="left:28px;right:24px;top:40px"><img class="logo" src="../../../../assets/branding/pleya_wordmark.png"><span class="search">${I.search}</span>${face(false,true)}<span class="mono ava">M</span></div>
  <div class="chips" style="left:28px;top:100px"><span>Series</span><span>Films</span></div>
  <div class="sec" style="left:28px;top:160px">Verder kijken</div>
  <div class="land" style="left:28px;top:202px"><div><img src="${P}sintel-wide.jpg"><b>Sintel</b></div><div><img src="${P}bbb-wide.jpg"><b>Big Buck Bunny</b></div><div><img src="${P}sintel-wide.jpg" style="object-position:80% 50%"><b>Sintel</b></div><div><img src="${P}bbb-wide.jpg" style="object-position:20% 50%"><b>Big Buck Bunny</b></div></div>
  <div class="sec" style="left:28px;top:410px">Recent toegevoegde films</div>
  <div class="rail" style="left:28px;top:452px"><div><img src="${P}tears-poster.jpg"><b>Tears of Steel</b></div><div><img src="${P}spring-poster.jpg"><b>Spring</b></div><div><img src="${P}elephants-poster.jpg"><b>Elephants Dream</b></div><div><img src="${P}charge-poster.jpg"><b>Charge</b></div><div><img src="${P}coffeerun-poster.jpg"><b>Coffee Run</b></div><div><img src="${P}dweebs-poster.jpg"><b>Dweebs</b></div><div><img src="${P}caminandes-poster.jpg"><b>Caminandes</b></div></div>
  <div class="tabbar" style="height:74px"><div class="on">${I.home}Home</div><div>${I.tv}Series</div><div>${I.film}Films</div><div><span class="mono tava">M</span>Mijn Pleya</div></div>
</div><div class="dim"></div>
<div class="ball" style="left:300px;width:620px;top:120px">
  <div class="asked"><span>Je vroeg: </span>Welke animatiefilms heb ik nog niet gezien?</div>
  <div class="answer">Drie nog niet. Spring staat niet op je server, die kan ik aanvragen.</div>
  <div class="cards" style="display:grid;grid-template-columns:1fr 1fr">
    ${mc('tears-poster.jpg','Tears of Steel',2012,'Film · 12 min',['ok','In je bibliotheek · NAS'])}
    ${mc('elephants-poster.jpg','Elephants Dream',2006,'Film · 11 min',['ok','In je bibliotheek · NAS'])}
    ${mc('spring-poster.jpg','Spring',2019,'Film · 8 min',['ask','Aan te vragen'])}
  </div>
  ${fu(['Wat kan ik vanavond kijken?','Wat is er net toegevoegd?','Wat staat er nog op mijn lijst?'])}
  <div class="input" style="position:relative;left:0;right:0;margin-top:16px"><span class="txt ph">Vraag verder</span><span class="send off">${I.mic}</span></div>
</div>` + tail(940, 470, 'right') + bp('bigp-vinger_presenteren', {left:925, top:360, width:250});""", size=(1180, 820))

page('39-j-tvos-variant', '39 J tvOS-variant', r"""document.body.innerHTML = `<img src="../../tvos-unified/home-reference.png" style="position:absolute;inset:0;width:1920px;height:1080px;object-fit:cover">
<div class="dim" style="background:rgba(0,0,0,.55)"></div>
<div class="ball zoom15" style="left:330px;width:620px;top:60px">
  <div class="asked"><span>Je vroeg: </span>Welke animatiefilms heb ik nog niet gezien?</div>
  <div class="answer">Drie nog niet. Spring staat niet op je server, die kan ik aanvragen.</div>
  <div class="cards">
    <div style="border-radius:16px;box-shadow:0 0 0 2px #fff">${mc('tears-poster.jpg','Tears of Steel',2012,'Film · 12 min',['ok','In je bibliotheek · NAS'])}</div>
    ${mc('elephants-poster.jpg','Elephants Dream',2006,'Film · 11 min',['ok','In je bibliotheek · NAS'])}
    ${mc('spring-poster.jpg','Spring',2019,'Film · 8 min',['ask','Aan te vragen'])}
  </div>
  ${fu(['Wat kan ik vanavond kijken?','Wat is er net toegevoegd?','Wat staat er op mijn lijst?'])}
</div>` + bp('bigp-vinger_presenteren', {left:1450, top:380, width:440});""", size=(1920, 1080))

only = sys.argv[1:]
for name, (title, js, size) in PAGES.items():
    if only and name not in only: continue
    (D / f'{name}.html').write_text(f'''<!doctype html><html lang="nl"><head><meta charset="utf-8"><title>{title}</title>
<link rel="stylesheet" href="bp39.css"><script src="bp39.js"></script>{'<style>body{width:%dpx;height:%dpx}</style>' % size if size != (402, 874) else ''}</head><body><script>
{js}
</script></body></html>
''')
    print(name, size[0], size[1])
