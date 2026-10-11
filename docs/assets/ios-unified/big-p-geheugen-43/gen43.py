"""Mockupset 43: schrijft de HTML en rendert de PNG's op 2x.

python3 gen43.py            alle HTML plus PNG's
python3 gen43.py --html     alleen HTML
python3 gen43.py 43-b-bewerken   een enkel beeld
"""
import pathlib, sys
D = pathlib.Path(__file__).resolve().parent
PAGES = {}

def page(name, title, js, size=(402, 874), cls=''):
    PAGES[name] = (title, js, size, cls)

page('43-a-hoofdscherm', '43 A Geheugen', 'document.body.innerHTML = mainScreen();')
page('43-a-hoofdscherm-onder', '43 A Geheugen, einde van de scroll', 'document.body.innerHTML = mainScreen(); toEnd();')

page('43-b-bewerken', '43 B Herinnering bewerken', r"""document.body.innerHTML = mainScreen() + `<div class="dim"></div>
<div class="sheet"><div class="grab"></div><h2>Herinnering</h2>
  <div class="flabel"><span>Tekst</span><span>21/200</span></div>
  <div class="field">Houdt niet van horror</div>
  <div class="flabel"><span>Categorie</span></div>
  <div class="wrap">${chips('Niet voor mij', false)}</div>
  <div class="meta"><div><span>Herkomst</span><span>Voorgesteld door Big P, door jou bevestigd</span></div><div><span>Toegevoegd op</span><span>2 oktober 2026</span></div><div><span>Laatst gewijzigd</span><span>9 oktober 2026</span></div></div>
  <div class="acts"><div class="btn">Annuleren</div><div class="btn pri">Opslaan</div></div>
  <div class="tbtn danger" style="margin-top:6px">Verwijderen</div>
</div><div class="homeind"></div>`;""")

page('43-c-toevoegen', '43 C Herinnering toevoegen', r"""document.body.innerHTML = mainScreen() + `<div class="dim"></div>
<div class="sheet" style="bottom:292px;border-radius:20px 20px 0 0;padding-bottom:16px"><div class="grab"></div><h2>Herinnering toevoegen</h2>
  <div class="flabel"><span>Tekst</span><span>0/200</span></div>
  <div class="field active"><span class="caret"></span><span class="ph">Bijvoorbeeld: ik houd niet van horror</span></div>
  <div class="flabel"><span>Categorie</span></div>
  <div class="wrap">${chips('Voorkeuren', false)}</div>
  <div class="hint">Sla geen wachtwoorden of medische gegevens op.</div>
  <div class="acts"><div class="btn">Annuleren</div><div class="btn off">Opslaan</div></div>
</div>` + keyboard() + '<div class="homeind"></div>';""")

page('43-d-wissen', '43 D Alles wissen bevestigen', r"""document.body.innerHTML = mainScreen() + `<div class="dim"></div>
<div class="dialog"><h2>Alle herinneringen wissen?</h2>
  <p>Big P vergeet alles wat hij over dit profiel heeft onthouden. Dit kan niet ongedaan worden gemaakt.</p>
  <div class="acts"><div class="btn pri">Annuleren</div><div class="btn" style="background:transparent;color:var(--accent)">Wissen</div></div>
</div>`; toEnd();""")

page('43-e-uit', '43 E Geheugen uit', r"""document.body.innerHTML = status() + bar() + `<div class="scroll">
  ${toggleCard(false, {callout:false})}
  <div class="card notice" style="margin-top:12px;border:1px solid var(--line)"><b>Geheugen staat uit.</b>Big P onthoudt niets en gebruikt niets. Bestaande herinneringen blijven bewaard tot je ze wist.</div>
  <div class="dimmed">${searchField()}<div class="fchips">${chips()}</div>
  <div class="glabel">Herinneringen<i>6 herinneringen</i></div>${memList()}</div>
</div>` + tabbar();""")

page('43-f-leeg', '43 F Nog geen herinneringen', r"""document.body.innerHTML = status() + bar() + `<div class="scroll">
  ${toggleCard(true)}
  <div class="glabel">Herinneringen<i>0 herinneringen</i></div>
  <div class="card empty"><div class="ring">${I.note}</div><b>Nog geen herinneringen.</b><p>Zeg tegen Big P 'onthoud dat ...' of voeg er zelf een toe.</p>
    <div style="margin-top:18px">${addBtn()}</div></div>
  <div style="margin-top:12px">${askRow()}</div>
  <div class="glabel">Uit je kinderprofiel</div>${agesRow()}
</div>` + tabbar();""")

page('43-g-gesprek', '43 G Onthouden in het gesprek', r"""document.body.innerHTML = homeBg() + tabbar('home') + `<div class="dim"></div>
<div class="moment" style="top:62px">1. Big P stelt voor, jij beslist</div>
<div class="ball cf" style="left:12px;right:12px;top:84px">
  <div class="asked"><span>Je vroeg: </span>Iets spannends voor vanavond, maar geen horror, daar houd ik niet van.</div>
  <h3>Zal ik dit onthouden?</h3>
  <div class="rows"><div><span>Herinnering</span><b>Houdt niet van horror</b></div><div><span>Categorie</span><b>Niet voor mij</b></div></div>
  <div class="btns"><span class="pill">Onthouden</span><span class="pill pri">Niet onthouden</span></div>
</div>
<div class="moment" style="top:410px">2. Je vraagt er zelf om</div>
<div class="ball" style="left:12px;right:12px;top:432px">
  <div class="asked"><span>Je vroeg: </span>Onthoud dat we op vrijdag met het gezin kijken</div>
  <div class="answer">Onthouden: kijkt op vrijdagavond met het gezin.</div>
  <span class="link">Bekijk geheugen${I.chev}</span>
</div>` + tail(320, 626) + bp('bigp-duim_presenteren', {left:214, top:606, width:180});""", cls='chat')

page('43-h-ipad', '43 H iPad liggend', r"""const cat = (n, c, on) => `<div class="srow ${on ? 'sel' : ''}" style="min-height:40px;padding:8px 14px"><div class="body"><div class="t" style="font-size:15px">${n}</div></div><span class="count">${c}</span></div>`;
document.body.innerHTML = `<div class="status"><span>9:41  zo 11 okt</span><span style="font-size:14px">100%</span></div>` + bar() + `<div class="cols">
  <div class="col">
    ${toggleCard(true)}${searchField()}
    <div class="glabel">Categorieën</div>
    <div class="card">${cat('Alles', MEM.length, true)}${CATS.map((c) => cat(c, countOf(c))).join('')}</div>
    <div style="margin-top:12px">${agesRow()}</div>
  </div>
  <div class="col">
    <div class="glabel">Herinneringen<i>6 herinneringen</i></div>
    ${memList({sel:0, chev:false})}
    <div style="margin-top:auto">${addBtn()}</div>
    <div style="margin-top:10px">${askRow()}</div>
    ${wipe()}
  </div>
  <div class="col">
    <div class="glabel">Geselecteerd</div>
    <div class="panel"><h2>Herinnering</h2>
      <div class="flabel"><span>Tekst</span><span>21/200</span></div>
      <div class="field">Houdt niet van horror</div>
      <div class="flabel"><span>Categorie</span></div>
      <div class="wrap">${chips('Niet voor mij', false)}</div>
      <div class="meta"><div><span>Herkomst</span><span>Voorgesteld door Big P, door jou bevestigd</span></div><div><span>Toegevoegd op</span><span>2 oktober 2026</span></div><div><span>Laatst gewijzigd</span><span>9 oktober 2026</span></div></div>
      <div class="acts"><div class="btn">Annuleren</div><div class="btn pri">Opslaan</div></div>
      <div class="tbtn danger" style="margin-top:6px">Verwijderen</div>
    </div>
  </div>
</div>` + tabbar();""", size=(1180, 820), cls='pad')

page('43-i-tvos', '43 I tvOS', r"""const cat = (n, c, on) => `<div class="row compact ${on ? 'sel' : ''}"><div class="body"><div class="t">${n}</div></div><span class="val">${c}</span></div>`;
const act = (ic, t) => `<div class="row compact">${ic}<div class="body"><div class="t">${t}</div></div>${I.chev}</div>`;
document.body.innerHTML = `<nav class="topnav"><div class="pchip">M</div><div class="cluster"><span class="nsearch">${I.search}</span><span class="item">Home</span><span class="item">Series</span><span class="item">Films</span><span class="item">Live TV</span><span class="item on">Mijn Pleya</span></div><div class="wordmark"><img src="../../tvos-unified/src/assets/pleya_wordmark.png" style="height:52px;display:block"></div></nav>
<div class="page">
  <div class="page-title">Geheugen</div>
  <div class="crumb">Mijn Pleya ▸ Instellingen ▸ Big P ▸ Geheugen</div>
  <div class="two">
    <div>
      <div class="rows"><div class="row"><div class="body"><div class="t">Geheugen gebruiken</div><div class="s">Alleen voor dit profiel, alleen op dit apparaat</div></div><span class="val">Aan</span>${I.chev}</div></div>
      <div class="foot">Big P onthoudt wat je vertelt en gebruikt het bij je vragen. Gebruik je een cloudmodel, dan gaan relevante herinneringen mee met je vraag.</div>
      <div class="group-label">Categorieën</div>
      <div class="grid2">${cat('Alles', MEM.length, true)}${CATS.map((c) => cat(c, countOf(c))).join('')}</div>
      <div class="group-label">Acties</div>
      <div class="rows">${act(I.plus, 'Herinnering toevoegen')}${act(I.chat, 'Vraag Big P')}${act(I.trash, 'Alle herinneringen wissen')}</div>
    </div>
    <div>
      <div class="group-label">Herinneringen <span>6 herinneringen · Alles</span></div>
      <div class="rows">${MEM.map((m, i) => `<div class="row ${i === 0 ? 'focus' : ''}"><div class="body"><div class="t">${m[0]}</div><div class="s">${m[1]} · ${m[2]}</div></div>${I.chev}</div>`).join('')}</div>
      <div class="group-label">Uit je kinderprofiel</div>
      <div class="rows"><div class="row"><div class="body"><div class="t">Leeftijden kinderen</div><div class="s">Beheerd bij Kinderprofiel</div></div><span class="val">8 en 11</span>${I.chev}</div></div>
    </div>
  </div>
</div>`;""", size=(1920, 1080), cls='tv')

args = [a for a in sys.argv[1:] if not a.startswith('--')]
todo = [n for n in PAGES if not args or n in args]
for name in todo:
    title, js, size, cls = PAGES[name]
    (D / f'{name}.html').write_text(f'''<!doctype html><html lang="nl"><head><meta charset="utf-8"><title>{title}</title>
<link rel="stylesheet" href="bp43.css"><script src="bp43.js"></script></head><body class="{cls}"><script>
{js}
</script></body></html>
''')
    print(name, size[0], size[1])

if '--html' not in sys.argv:
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for name in todo:
            w, h = PAGES[name][2]
            pg = browser.new_page(viewport={'width': w, 'height': h}, device_scale_factor=2)
            pg.goto((D / f'{name}.html').as_uri())
            pg.evaluate('document.fonts.ready')
            pg.wait_for_timeout(300)
            pg.screenshot(path=str(D / f'{name}.png'))
            pg.close()
        browser.close()
