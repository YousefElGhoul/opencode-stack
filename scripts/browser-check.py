#!/usr/bin/env python3
"""Exercise the actual Playwright MCP HTTP transport, navigation and DOM rendering."""
import json
import sys
import urllib.request


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: browser-check http://127.0.0.1:4321")
    endpoint = "http://127.0.0.1:8931/mcp"
    session = None
    sequence = 0

    def rpc(method, params):
        nonlocal session, sequence
        sequence += 1
        headers = {"Content-Type": "application/json", "Accept": "application/json, text/event-stream"}
        if session:
            headers["Mcp-Session-Id"] = session
            headers["MCP-Protocol-Version"] = "2024-11-05"
        body = {"jsonrpc": "2.0", "method": method, "params": params}
        if not method.startswith("notifications/"):
            body["id"] = sequence
        request = urllib.request.Request(endpoint, data=json.dumps(body).encode(), headers=headers)
        with urllib.request.urlopen(request, timeout=90) as response:
            session = response.headers.get("Mcp-Session-Id", session)
            text = response.read().decode()
            if not text:
                return {}
            if response.headers.get("Content-Type", "").startswith("text/event-stream"):
                messages = [json.loads(line[6:]) for line in text.splitlines() if line.startswith("data: ")]
                result = next(message for message in messages if message.get("id") == sequence)
            else:
                result = json.loads(text)
            if "error" in result:
                raise RuntimeError(result["error"])
            result = result.get("result", {})
            if result.get("isError"):
                raise RuntimeError(result.get("content"))
            return result

    def tool(name, arguments):
        result = rpc("tools/call", {"name": name, "arguments": arguments})
        print(f"{name}:")
        for item in result.get("content", []):
            if item.get("type") == "text":
                print(item["text"])
        return result

    try:
        rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                           "clientInfo": {"name": "opencode-stack-browser-check", "version": "1.0"}})
        rpc("notifications/initialized", {})
        names = {tool["name"] for tool in rpc("tools/list", {}).get("tools", [])}
        assert {"browser_navigate", "browser_snapshot", "browser_evaluate"} <= names
        tool("browser_navigate", {"url": sys.argv[1]})
        tool("browser_snapshot", {})
        tool("browser_evaluate", {"function": """() => {
          const body = document.body;
          const box = body.getBoundingClientRect();
          if (!body.innerText.trim() || box.width <= 0 || box.height <= 0)
            throw new Error('Page did not render visible content');
          return {title: document.title, url: location.href, textLength: body.innerText.length,
            width: box.width, height: box.height, headings: [...document.querySelectorAll('h1,h2')].map(x => x.innerText)};
        }"""})
        tool("browser_close", {})
        print("PASS: Playwright MCP navigated, rendered, and inspected the page")
    finally:
        if session:
            request = urllib.request.Request(endpoint, method="DELETE", headers={"Mcp-Session-Id": session})
            try:
                urllib.request.urlopen(request, timeout=10).close()
            except Exception:
                pass


if __name__ == "__main__":
    main()
