"""The browser version loads and starts: the engine boots, the first
screen draws, typing works through the page's text bar, and nothing in
the game's scripts errors. Software rendering, so no
judgement on speed here.
    python3 .github/web_smoke.py http://127.0.0.1:8765/index.html [screenshot.png]
"""
import asyncio
import sys
import time

from playwright.async_api import async_playwright

URL = sys.argv[1]
SHOT = sys.argv[2] if len(sys.argv) > 2 else "web_smoke.png"


async def main() -> int:
    async with async_playwright() as p:
        b = await p.chromium.launch(args=["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--ignore-gpu-blocklist"])
        ctx = await b.new_context(viewport={"width": 1280, "height": 600}, has_touch=True)
        pg = await ctx.new_page()
        logs = []
        pg.on("console", lambda m: logs.append(m.type + ": " + m.text))
        pg.on("pageerror", lambda e: logs.append("PAGEERROR: " + str(e)))
        t0 = time.time()
        await pg.goto(URL)
        ok = True
        try:
            await pg.wait_for_function("!document.getElementById('status')", timeout=180000)
            print("PASS  the game loaded and started (%.1f s)" % (time.time() - t0))
        except Exception as e:  # noqa: BLE001
            print("FAIL  the game didn't start: %s" % e)
            ok = False
        await pg.wait_for_timeout(12000)
        png = await pg.screenshot(path=SHOT, timeout=120000)
        # The hub has drawn: a flat screen compresses to almost nothing.
        if len(png) < 30000:
            print("FAIL  the screen is blank (%d byte screenshot)" % len(png))
            ok = False
        else:
            print("PASS  the menu is on screen (%d byte screenshot)" % len(png))
        # And a race draws its 3D world (index.html?race=: straight onto the
        # grid). A world that isn't drawn (sky and HUD only) is a small,
        # mostly flat picture; the grid with 20 cars is several times bigger.
        # Three kinds of venue: open parkland, the densest forest, a city.
        # Typing in a browser (the first screen is Create your driver): tap
        # the name box, the page's text bar opens, what's typed goes back
        # to the game.
        try:
            await pg.evaluate("""() => { window.__typed = []; const o = window.__apexText.open;
                window.__apexText.open = function (t, ph, m, cb) { return o.call(this, t, ph, m, function (v, d) { window.__typed.push([v, d]); return cb(v, d); }); }; }""")
            await pg.touchscreen.tap(1280 * 0.30, 600 * 0.215)
            await pg.wait_for_function("document.getElementById('textbar').classList.contains('on')", timeout=20000)
            await pg.tap("#textin")
            await pg.keyboard.type("Racer")
            await pg.click("#textdone")
            await pg.wait_for_timeout(1500)
            typed = await pg.evaluate("window.__typed")
            if typed and typed[-1] == ["Racer", True]:
                print("PASS  typing: the name box opens the page's text bar and the name reaches the game")
            else:
                print("FAIL  typing: the game got %s" % typed)
                ok = False
        except Exception as e:  # noqa: BLE001
            print("FAIL  typing: the text bar didn't open (%s)" % e)
            ok = False
        for tid in ["silvermoor", "ardennes", "marina"]:
            await pg.goto(URL + "?race=" + tid)
            try:
                await pg.wait_for_function("!document.getElementById('status')", timeout=180000)
                await pg.wait_for_timeout(15000)
                race_png = await pg.screenshot(path=SHOT.replace(".png", "_%s.png" % tid), timeout=180000)
                if len(race_png) < 400000:
                    print("FAIL  %s: the race's 3D world isn't drawn (%d byte screenshot)" % (tid, len(race_png)))
                    ok = False
                else:
                    print("PASS  %s: the race draws the track and the grid (%d byte screenshot)" % (tid, len(race_png)))
            except Exception as e:  # noqa: BLE001
                print("FAIL  %s: the race didn't start: %s" % (tid, e))
                ok = False
        bad = [l for l in logs if "PAGEERROR" in l or "SCRIPT ERROR" in l or "Parse Error" in l]
        for l in logs[-25:]:
            print("    " + l[:200])
        if bad:
            print("FAIL  errors in the browser console:")
            for l in bad[:10]:
                print("    " + l[:300])
            ok = False
        else:
            print("PASS  no script errors")
        await b.close()
        print("ALL CHECKS PASSED" if ok else "CHECKS FAILED")
        return 0 if ok else 1


sys.exit(asyncio.run(main()))
