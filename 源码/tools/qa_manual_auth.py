"""Submit the real game login form; fixtures must never bypass manual login."""
def login(page, name, password, mobile=False, expect_ok=True):
    dimensions = page.evaluate("({w:canvas.clientWidth,h:canvas.clientHeight})")
    w, h = dimensions['w'], dimensions['h']
    unit = min(max(min(w/1280,h/720),.65),1.6,(w-24)/480,(h-80)/337)
    x, y = (w-480*unit)/2, max(72*unit,h*.215)
    def select(fx,fy):
        at=(x+fx*unit,y+fy*unit)
        (page.touchscreen.tap if mobile else page.mouse.click)(*at)
        page.wait_for_timeout(150)
    for fy,value in [(43,name),(115,password)]:
        select(245,fy)
        page.keyboard.press('Control+A')
        if mobile:page.keyboard.insert_text(value)
        else:page.keyboard.type(value)
    with page.expect_response(lambda response:response.url.endswith('/api/login'),timeout=30000) as response:
        select(406,80)
    assert response.value.ok is expect_ok, 'Unexpected manual login result: '+str(response.value.status)
    return response.value
