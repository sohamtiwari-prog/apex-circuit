"""The browser version loads and starts: the engine boots, the hub draws,
and nothing in the game's scripts errors. Software rendering, so no
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
        await pg.goto(URL + "?race=silvermoor")
        try:
            await pg.wait_for_function("!document.getElementById('status')", timeout=180000)
            await pg.wait_for_timeout(15000)
            race_png = await pg.screenshot(path=SHOT.replace(".png", "_race.png"), timeout=120000)
            if len(race_png) < 400000:
                print("FAIL  the race's 3D world isn't drawn (%d byte screenshot)" % len(race_png))
                ok = False
            else:
                print("PASS  the race draws the track and the grid (%d byte screenshot)" % len(race_png))
        except Exception as e:  # noqa: BLE001
            print("FAIL  the race didn't start: %s" % e)
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
