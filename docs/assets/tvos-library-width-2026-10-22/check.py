from pathlib import Path
import json
from playwright.sync_api import sync_playwright
out=Path('/tmp/pleya-library-width-evidence');out.mkdir(parents=True,exist_ok=True);results=[]
with sync_playwright() as p:
 browser=p.chromium.launch(channel="chrome")
 for w,h in [(1920,1080),(1038,584)]:
  page=browser.new_page(viewport={'width':w,'height':h},device_scale_factor=1)
  errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.goto('http://127.0.0.1:8794/tvos-library-width-2026-10-22/?clean=1');page.wait_for_selector('.card.selected');page.evaluate('document.fonts.ready');page.wait_for_function('Array.from(document.images).every(i=>i.complete && i.naturalWidth>0)')
  page.screenshot(path=str(out/f'{w}-series-entry.png'))
  for _ in range(5):page.keyboard.press('ArrowRight')
  page.wait_for_timeout(300)
  assert page.locator('.card.selected').get_attribute('aria-label').startswith('The White Lotus')
  box=page.locator('.card.selected .art').bounding_box();assert box['x']>20 and box['x']+box['width']<w-20
  page.screenshot(path=str(out/f'{w}-series-last-column.png'))
  page.keyboard.press('ArrowDown');page.wait_for_timeout(300)
  assert page.locator('#screen').evaluate('(e)=>e.classList.contains("browsing")')
  b=page.locator('.card.selected').bounding_box();assert b['y']>0 and b['y']+b['height']<h
  assert page.locator('.card.selected .meta').bounding_box()['y']<h
  art=page.locator('.card.selected .art').bounding_box();title=page.locator('.card.selected .title').bounding_box()
  scale=min(w/1920,h/1080)
  clear_gap=(title['y']-art['y']-art['height'])/scale-12*1.035
  assert clear_gap>=12, f'Focus ring needs clear space before title: {clear_gap}'
  page.screenshot(path=str(out/f'{w}-series-browse.png'))
  page.keyboard.press('ArrowUp');page.wait_for_timeout(300)
  assert not page.locator('#screen').evaluate('(e)=>e.classList.contains("browsing")')
  page.keyboard.press('Escape');assert page.locator('[data-page="series"]').evaluate('(e)=>e===document.activeElement')
  page.keyboard.press('ArrowDown');assert page.locator('.card.selected').count()==1
  page.keyboard.press('f');page.wait_for_timeout(300)
  assert page.locator('h1').inner_text()=='Alle films'
  page.wait_for_function('Array.from(document.images).every(i=>i.complete && i.naturalWidth>0)')
  page.screenshot(path=str(out/f'{w}-films-entry.png'))
  page.keyboard.press('ArrowDown');page.wait_for_timeout(300)
  page.screenshot(path=str(out/f'{w}-films-browse.png'))
  for _ in range(5):page.keyboard.press('ArrowRight')
  page.wait_for_timeout(300)
  assert page.locator('.card.selected .title').inner_text()=='Everything Everywhere All at Once'
  assert page.locator('.card.selected .title').evaluate('(e)=>getComputedStyle(e).webkitLineClamp==="2" && e.clientHeight===64')
  assert page.locator('.card.selected').get_attribute('aria-label').startswith('Everything Everywhere All at Once')
  page.screenshot(path=str(out/f'{w}-films-long-title.png'))
  page.keyboard.press('ArrowRight');assert page.locator('.card.selected .title').inner_text()=='Everything Everywhere All at Once'
  page.keyboard.press('ArrowDown');page.keyboard.press('ArrowDown');assert page.locator('.card.selected').count()==1
  page.keyboard.press('Escape');page.keyboard.press('ArrowDown');page.wait_for_timeout(300)
  assert not page.locator('#screen').evaluate('(e)=>e.classList.contains("browsing")')
  page.keyboard.press('Escape');page.keyboard.press('ArrowLeft');page.keyboard.press('Enter');page.keyboard.press('ArrowDown')
  assert page.locator('.card.selected .title').inner_text()=='The Diplomat', 'DOWN after activating Series tab enters row 0'
  page.keyboard.press('Escape');page.keyboard.press('ArrowRight');page.keyboard.press('Enter');page.keyboard.press('ArrowDown')
  assert page.locator('.card.selected .title').inner_text()=='Oppenheimer', 'DOWN after activating Films tab enters row 0'
  assert not errors,errors
  results.append({'viewport':[w,h],'result':'PASS','checks':['images','six columns','edge focus safe','focused art-title gap >=12px','active card and metadata visible','long title','row traversal','bounds','escape to nav and return','film-series switch','top tab activation enters row 0','console errors']})
  page.close()
 browser.close()
(out/'checks.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))
