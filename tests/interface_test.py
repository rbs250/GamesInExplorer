"""Synthetic browser smoke test; requires Playwright and installed Edge."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread

from playwright.sync_api import expect, sync_playwright

web = Path(__file__).resolve().parents[1] / "web"


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, *args):
        pass


server = ThreadingHTTPServer(("127.0.0.1", 0), partial(Handler, directory=str(web)))
Thread(target=server.serve_forever, daemon=True).start()
try:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(channel="msedge", headless=True)
        page = browser.new_page(viewport={"width": 1100, "height": 700})
        page.add_init_script(
            "window.sent=[];window.chrome={webview:{postMessage:m=>window.sent.push(m),addEventListener:()=>{}}};"
        )
        errors = []
        page.on("pageerror", lambda error: errors.append(str(error)))
        page.route(
            "**/library.json?*",
            lambda route: route.fulfill(json={"games": [
                {"id": "steam-100001", "name": "Example Installed", "platform": "Steam", "cover": "", "installed": True, "sizeGB": 1, "folder": ""},
                {"id": "steam-200002", "name": "Example Owned", "platform": "Steam", "cover": "", "installed": False, "sizeGB": 0, "folder": ""},
            ]}),
        )
        page.route("**/game-details.json?*", lambda route: route.fulfill(json={}))
        page.goto(f"http://127.0.0.1:{server.server_port}/index.html")
        expect(page.locator(".cover")).to_have_count(2)
        expect(page.locator("#library-count")).to_have_text("2 games · 1 installed")
        expect(page.locator("#game-title")).to_have_text("Example Owned")
        expect(page.locator("#play")).to_have_attribute("aria-label", "Install in Steam Example Owned")
        page.locator("#play").click()
        assert page.evaluate("window.sent.pop()") == "launch:steam-200002"
        page.get_by_role("button", name="Game info", exact=True).click()
        expect(page.get_by_role("dialog")).to_be_visible()
        expect(page.locator("#box-synopsis")).not_to_be_empty()
        page.keyboard.press("Escape")
        page.get_by_role("searchbox").fill("Installed")
        expect(page.locator(".cover")).to_have_count(1)
        expect(page.locator("#game-title")).to_have_text("Example Installed")
        page.get_by_role("button", name="Grid view", exact=True).click()
        expect(page.locator("#grid")).to_be_visible()
        assert errors == [], errors
        empty = browser.new_page()
        empty.goto(f"http://127.0.0.1:{server.server_port}/index.html")
        expect(empty.locator("#library-count")).to_have_text("0 games · 0 installed")
        expect(empty.locator("#empty")).to_be_visible()
        empty.close()
        browser.close()
finally:
    server.shutdown()
print("PASS: synthetic installed and owned UI, launch mapping, details, search, and grid.")
