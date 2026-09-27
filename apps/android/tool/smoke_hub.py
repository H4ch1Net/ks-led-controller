"""Exercise the production Dart hub client against a temporary simulator API.

Run from the repo root: python -m apps.android.tool.smoke_hub --dart PATH_TO_DART
"""
import argparse
import asyncio
import json
from pathlib import Path
import secrets
import tempfile

from aiohttp.test_utils import TestServer
from ks_light.hub import create_app
from ks_light.protocol import color


async def main(dart):
    root = Path(__file__).resolve().parents[3]
    lights = json.loads((root / "examples/hub-multi-light.example.json").read_text(encoding="utf-8"))["lights"]
    lights[0]["calibration"] = {"rgb_gains": [1, .3, .75]}
    library = json.loads((root / "examples/hub-library.example.json").read_text(encoding="utf-8"))
    token = secrets.token_urlsafe(32)
    writes = []

    async def sender(light, packets):
        writes.append((light["id"], packets))

    server = TestServer(create_app(lights, token, sender=sender, library=library))
    await server.start_server()
    process = None
    try:
        with tempfile.TemporaryDirectory() as folder:
            token_path = Path(folder) / "token.txt"
            token_path.write_text(token, encoding="utf-8")
            process = await asyncio.create_subprocess_exec(str(Path(dart).resolve()),
                str(root / "apps/android/tool/hub_library_smoke.dart"),
                str(server.make_url("/")), str(token_path),
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
            stdout, stderr = await asyncio.wait_for(process.communicate(), 45)
            if process.returncode != 0:
                raise RuntimeError("Dart API smoke failed: " + stderr.decode(errors="replace").replace(token, "[redacted]"))
            assert len(writes) == 10
            desk = [packets for target, packets in writes if target == "desk"]
            sofa = [packets for target, packets in writes if target == "sofa"]
            assert len(desk) == len(sofa) == 5
            assert desk[1][-1] == color(255, 57, 90, "floor", 35)
            assert desk[2][-1] == color(255, 57, 90, "floor", 60)
            assert sofa[2][-1] == bytes([0x5c, 0, 137, 35, 60, 0, 0xc5])
            assert desk[3][-1] == color(100, 60, 60, "floor", 67)
            assert sofa[3][-1] == color(100, 200, 80, "floor", 67)
            assert desk[4][-1] == sofa[4][-1] == bytes([0x5c, 0, 137, 35, 35, 0, 0xc5])
            assert token.encode() not in stdout + stderr
            print(stdout.decode().strip())
    finally:
        if process and process.returncode is None:
            process.kill()
            await process.communicate()
        await server.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", required=True)
    asyncio.run(main(parser.parse_args().dart))
