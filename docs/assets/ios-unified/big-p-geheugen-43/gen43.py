"""Mockupset 43: schrijft de HTML en rendert de PNG's op 2x.

python3 gen43.py            alle HTML plus PNG's
python3 gen43.py --html     alleen HTML
python3 gen43.py 43-e-bewerken   een enkel beeld
"""
import pathlib, sys
D = pathlib.Path(__file__).resolve().parent
PAGES = {}

def page(name, title, js, size=(402, 874), cls=''):
    PAGES[name] = (title, js, size, cls)

SHEET_EDIT = r"""`<div class="dim"></div>
<div class="sheet"><div class="grab"></div><h2>Herinnering</h2>
  <div class="flabel"><span>Tekst</span><span>21/200</span></div>
  <div class="field">Houdt niet van horror</div>
  <div class="flabel"><span>Categorie</span></div>
  <div class="wrap">${chips('Niet voor mij', false)}</div>
  <div class="meta"><div><span>Herkomst</span><span>Voorgesteld door Big P, door jou bevestigd</span></div><div><span>Toegevoegd op</span><span>2 oktober 2026</span></div><div><span>Laatst gewijzigd</span><span>9 oktober 2026</span></div></div>
  <div class="acts"><div class="btn">Annuleren</div><div class="btn pri">Opslaan</div></div>
  <div class="tbtn danger" style="margin-top:6px">Verwijderen</div>
</div><div class="homeind"></div>`"""

page('43-a-overzicht', '43 A Geheugenoverzicht', 'document.body.innerHTML = overviewScreen();')
page('43-a-overzicht-onder', '43 A Geheugenoverzicht, einde van de scroll', 'document.body.innerHTML = overviewScreen(); toEnd();')

page('43-b-genereren', '43 B Overzicht bijwerken', r"""document.body.innerHTML = status() + bar('Geheugen', {sub:'Bijwerken', menu:true}) + dots(402, 664) + tabbar();""")

page('43-c-menu', '43 C Menu', r"""document.body.innerHTML = overviewScreen() + `<div class="dim"></div>
<div class="sheet"><div class="grab"></div><h2>Geheugen</h2>
  <div class="card">${navRow('Herinneringen beheren', MEM.length)}</div>
  <div class="card">${switchRow(true)}</div>
  <div class="card">${navRow('Overzicht opnieuw schrijven')}</div>
  <div class="tbtn danger" style="margin-top:8px">Alle herinneringen wissen</div>
</div><div class="homeind"></div>`;""")

page('43-d-beheren', '43 D Herinneringen beheren', 'document.body.innerHTML = manageScreen();')

page('43-e-bewerken', '43 E Herinnering bewerken', 'document.body.innerHTML = manageScreen() + ' + SHEET_EDIT + ';')

page('43-f-toevoegen', '43 F Herinnering toevoegen', r"""document.body.innerHTML = manageScreen() + `<div class="dim"></div>
<div class="sheet" style="bottom:292px;border-radius:20px 20px 0 0;padding-bottom:16px"><div class="grab"></div><h2>Herinnering toevoegen</h2>
  <div class="flabel"><span>Tekst</span><span>0/200</span></div>
  <div class="field active"><span class="caret"></span><span class="ph">Bijvoorbeeld: ik houd niet van horror</span></div>
  <div class="flabel"><span>Categorie</span></div>
  <div class="wrap">${chips('Voorkeuren', false)}</div>
  <div class="hint">Sla geen wachtwoorden of medische gegevens op.</div>
  <div class="acts"><div class="btn">Annuleren</div><div class="btn off">Opslaan</div></div>
</div>` + keyboard() + '<div class="homeind"></div>';""")

page('43-g-wissen', '43 G Alles wissen bevestigen', r"""document.body.innerHTML = overviewScreen() + `<div class="dim" style="z-index:39"></div>
<div class="dialog"><h2>Alle herinneringen wissen?</h2>
  <p>Big P vergeet alles wat hij over dit profiel heeft onthouden. Dit kan niet ongedaan worden gemaakt.</p>
  <div class="acts"><div class="btn pri">Annuleren</div><div class="btn" style="background:transparent;color:var(--accent)">Wissen</div></div>
</div>`;""")

page('43-h-bijwerken', '43 H Bijwerken via het invoerveld', r"""document.body.innerHTML = overviewScreen({sub:'Wacht op je keuze', comp:{state:'sent', text:'We kijken tegenwoordig op zaterdag met het gezin'}}) + `
<div class="scrim" style="height:420px"></div>
<div class="replace" style="bottom:204px"><h3>Zal ik dit vervangen?</h3>
  <div class="pair"><div class="gone"><span>Verdwijnt</span><b>Kijkt op vrijdagavond met het gezin</b></div><div><span>Nieuw</span><b>Kijkt op zaterdagavond met het gezin</b></div></div>
  <div class="btns"><span class="pill">Vervangen</span><span class="pill pri">Niet vervangen</span></div>
</div>`;""")

page('43-i-uit', '43 I Geheugen uit', r"""document.body.innerHTML = status() + bar('Geheugen', {sub:'Uit', menu:true}) + `<div class="scroll ov">
  <div class="card empty state"><div class="ring">${I.note}</div><b>Geheugen staat uit.</b><p>Big P onthoudt niets en gebruikt niets. Bestaande herinneringen blijven bewaard tot je ze wist.</p>
    <div class="btn pri">Geheugen aanzetten</div></div>
</div>` + composer({state:'off'}) + tabbar();""")

page('43-j-leeg', '43 J Nog geen herinneringen', r"""document.body.innerHTML = status() + bar('Geheugen', {sub:'Nog leeg', menu:true}) + `<div class="scroll ov">
  <div class="card empty state"><div class="ring">${I.note}</div><b>Nog geen herinneringen.</b><p>Vertel Big P wat hij over je moet weten, bijvoorbeeld: onthoud dat ik niet van horror houd.</p></div>
</div>` + composer({state:'active'}) + tabbar();""")

page('43-k-gesprek', '43 K Onthouden in het gesprek', r"""document.body.innerHTML = homeBg() + tabbar('home') + `<div class="dim"></div>
<div class="moment" style="top:58px">Toelichting bij de mockup 1: eerst het antwoord, dan het voorstel</div>
<div class="ball" style="left:12px;right:12px;top:80px">
  <div class="asked"><span>Je vroeg: </span>Iets spannends voor vanavond, maar geen horror, daar houd ik niet van.</div>
  <div class="reply">Drie spannende titels zonder horror:</div>
  <div class="titles">Tears of Steel · Sintel · Cosmos Laundromat</div>
  <div class="propose"><h3>Zal ik dit onthouden?</h3>
    <div class="rows"><div><span>Herinnering</span><b>Houdt niet van horror</b></div><div><span>Categorie</span><b>Niet voor mij</b></div></div>
    <div class="btns"><span class="pill">Onthouden</span><span class="pill pri">Niet onthouden</span></div>
  </div>
</div>
<div class="moment" style="top:474px">Toelichting bij de mockup 2: je vraagt er zelf om</div>
<div class="ball" style="left:12px;right:12px;top:496px">
  <div class="asked"><span>Je vroeg: </span>Onthoud dat we op vrijdag met het gezin kijken</div>
  <div class="answer">Onthouden: kijkt op vrijdagavond met het gezin.</div>
  <span class="link">Bekijk geheugen${I.chev}</span>
</div>` + tail(320, 682) + bp('bigp-duim_presenteren', {left:232, top:670, width:160});""", cls='chat')

page('43-l-ipad', '43 L iPad liggend', r"""document.body.innerHTML = `<div class="status"><span>9:41  zo 11 okt</span><span style="font-size:14px">100%</span></div>` + bar('Geheugen', {sub:'Zojuist bijgewerkt'}) + `<div class="cols">
  <div class="read">${ovSections()}${ovFoot()}${composer()}</div>
  <div class="col side">
    <div class="card">${navRow('Herinneringen beheren', MEM.length)}</div>
    <div class="card">${switchRow(true)}</div>
    <div class="card">${navRow('Overzicht opnieuw schrijven')}</div>
    ${wipe()}
    ${deeper()}
  </div>
</div>` + tabbar();""", size=(1180, 820), cls='pad')

page('43-m-tvos', '43 M tvOS', r"""const row = (ic, t, {s = '', val = '', cls = 'compact'} = {}) => `<div class="row ${cls}">${ic}<div class="body"><div class="t">${t}</div>${s ? `<div class="s">${s}</div>` : ''}</div>${val ? `<span class="val">${val}</span>` : ''}${I.chev}</div>`;
document.body.innerHTML = `<nav class="topnav"><div class="pchip">M</div><div class="cluster"><span class="nsearch">${I.search}</span><span class="item">Home</span><span class="item">Series</span><span class="item">Films</span><span class="item">Live TV</span><span class="item on">Mijn Pleya</span></div><div class="wordmark"><img src="../../tvos-unified/src/assets/pleya_wordmark.png" style="height:52px;display:block"></div></nav>
<div class="page">
  <div class="page-title">Geheugen<span>Zojuist bijgewerkt</span></div>
  <div class="crumb">Mijn Pleya ▸ Instellingen ▸ Big P ▸ Geheugen</div>
  <div class="two ovtv">
    <div class="read">${ovSections()}${ovFoot()}</div>
    <div>
      <div class="rows">${row(I.chat, 'Vraag of werk bij', {s:'Opent het toetsenbord of dicteren', cls:'focus'})}</div>
      <div class="group-label">Duik dieper</div>
      <div class="rows">${QS.map((q) => row(I.follow, q)).join('')}</div>
      <div class="group-label">Beheer</div>
      <div class="rows">${row(I.note, 'Herinneringen beheren', {val:String(MEM.length)})}${row(I.toggle, 'Geheugen gebruiken: Aan')}${row(I.trash, 'Alle herinneringen wissen')}</div>
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
