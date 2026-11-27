"""Headless, muted browser acceptance of the shared interactive login page."""
from pathlib import Path
import argparse,json,secrets
from playwright.sync_api import sync_playwright
from qa_catalog_recovery import test_site

ROOT=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser();p.add_argument('--web',type=Path,required=True);args=p.parse_args()
out=ROOT/'.tools/qa/login-022/web';out.mkdir(parents=True,exist_ok=True)
evidence={'catalog_requests':0,'actions':[]};report={'passed':False,'checks':[],'page_errors':[],'engine_errors':[]}
name='qa_lw'+secrets.token_hex(3);secret='qa-web-895432'
def check(value,message):
 if not value:raise AssertionError(message)
 report['checks'].append(message)
with test_site(args.web.resolve(),evidence) as origin,sync_playwright() as p:
 browser=p.chromium.launch(executable_path='C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless=True,args=['--mute-audio','--enable-unsafe-swiftshader'])
 page=browser.new_page(viewport={'width':1440,'height':900});catalog={'ready':False};state={'room':None};auth={'registered':False}
 page.on('pageerror',lambda error:report['page_errors'].append(str(error)))
 page.on('console',lambda message:report['engine_errors'].append(message.text) if message.type=='error' and 'ERROR:' in message.text else None)
 def response(res):
  if res.ok and res.url.endswith('/api/catalog'):
   data=res.json();catalog['ready']=bool(data.get('vehicles')) and isinstance(data['vehicles'][0].get('name'),str)
  if res.ok and res.url.endswith('/api/register'):auth['registered']=True
  if res.ok and '/hd-api/api/' in res.url and not res.url.endswith('/api/catalog'):
   data=res.json()
   if 'profile' in data:state.update(data)
 page.on('response',response)
 def wait(condition,label):
  for _ in range(150):
   if condition():check(True,label);return
   page.wait_for_timeout(150)
  raise AssertionError(label)
 def click(x,y):page.mouse.click(x,y);page.wait_for_timeout(200)
 def shot(label):page.screenshot(path=str(out/(label+'.png')))
 try:
  page.goto(origin+'/hd/play/',wait_until='domcontentloaded')
  page.wait_for_selector('#status[hidden]',state='attached',timeout=120000)
  wait(lambda:catalog['ready'],'directory automatically recovers before authentication')
  page.wait_for_timeout(350);shot('login')
  page.mouse.move(222,375);page.wait_for_timeout(650);shot('hover')
  check(page.evaluate("(() => {const c=document.querySelector('canvas');return !c.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,cancelable:true}))})()"),'background interaction keeps browser context menu disabled')
  # The form follows native physical layout at 1440x900, independently of tiles.
  click(788.6,394.9)
  for x,y,text in [(725.6,214.9,name),(725.6,295.9,secret),(725.6,376.9,secret)]:
   click(x,y);page.keyboard.type(text)
  shot('registration')
  with page.expect_response(lambda res:res.url.endswith('/api/register'),timeout=15000) as registration:click(906.8,295.9)
  check(registration.value.ok,'real game form registers through the shared API')
  page.wait_for_timeout(120);shot('closing-door')
  page.wait_for_timeout(1500);shot('channel')
  click(210,355);click(345,837);page.wait_for_timeout(1500)
  shot('lobby');check(auth['registered'] and state.get('profile',{}).get('name')==name,'channel chooser enters lobby with the registered account')
  # Original lobby exit returns to this same account form.
  click(80,40);page.wait_for_timeout(1000);shot('after-logout')
  click(725.6,241.9);page.keyboard.press('Control+A');page.keyboard.type(name)
  click(725.6,322.9);page.keyboard.type(secret)
  click(788.6,451.1)
  with page.expect_response(lambda res:res.url.endswith('/api/login'),timeout=15000) as login:click(906.8,282.4)
  check(login.value.ok,'returning account signs in with the same form')
  page.wait_for_timeout(1600);shot('returning-channel')
  check(bool(page.evaluate("localStorage.getItem('burningchariot.hd.session')")),'remembered Web session stores a token')
  check(secret not in page.evaluate('JSON.stringify(localStorage)+JSON.stringify(sessionStorage)'),'browser stores no plaintext password')
  page.reload(wait_until='domcontentloaded')
  page.wait_for_selector('#status[hidden]',state='attached',timeout=120000)
  page.wait_for_timeout(2000);shot('remembered-channel')
  check(not report['page_errors'] and not report['engine_errors'],'no JavaScript exceptions or Godot errors')
  report.update(passed=True,catalog_requests=evidence['catalog_requests'],muted=True,headless=True)
 except Exception:
  shot('failure');raise
 finally:
  browser.close();(out/'report.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf8')
print(json.dumps(report,ensure_ascii=False))
