import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import led_control as cli
import led_menu as menu
from ks_light.controls import prepare_color
from ks_light.storage import StateStore, read_json, write_json, validate_presets


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "settings.json"

    def test_invalid_existing_file_is_preserved(self):
        self.path.write_text("{broken")
        with self.assertRaises(ValueError):
            write_json(self.path, {}, validate_presets)
        self.assertEqual(self.path.read_text(), "{broken")

    def test_invalid_preset_schema(self):
        for data in ([], {"red": {}}, {"red": {"r": True, "g": 0, "b": 0}},
                     {"red": {"r": 256, "g": 0, "b": 0}}):
            with self.subTest(data=data), self.assertRaises(ValueError):
                validate_presets(data)

    def test_valid_presets_round_trip_and_no_temp_files(self):
        data = {"red": {"r": 255, "g": 0, "b": 0}}
        write_json(self.path, data, validate_presets)
        self.assertEqual(read_json(self.path, validate_presets, {}), data)
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])

    def test_atomic_replace_failure_preserves_previous_file(self):
        write_json(self.path, {}, validate_presets)
        with patch("ks_light.storage.os.replace", side_effect=OSError("disk failure")):
            with self.assertRaises(OSError):
                write_json(self.path, {"red": {"r": 255, "g": 0, "b": 0}}, validate_presets)
        self.assertEqual(read_json(self.path, validate_presets, {}), {})
        self.assertEqual(list(self.path.parent.iterdir()), [self.path])

    def test_state_survives_restart_and_is_profile_specific(self):
        StateStore(self.path).put("one", "KS03~", [255, 0, 0], 64)
        state = StateStore(self.path).get("one", "KS03~")
        self.assertEqual(state["confirmation"], "unconfirmed")
        self.assertIsNone(StateStore(self.path).get("one", "KS03-"))
        self.assertIsNone(StateStore(self.path).get("two", "KS03~"))

    def test_dimming_preserves_rgb_and_new_color_preserves_brightness(self):
        old = {"rgb": [255, 0, 0], "brightness": 64}
        packet, rgb, brightness = prepare_color("KS03~", old, brightness=32)
        self.assertEqual(packet.hex().upper(), "5A0001FF0000002000A5")
        packet, rgb, brightness = prepare_color("KS03~", old, rgb=[0, 0, 255])
        self.assertEqual(packet.hex().upper(), "5A00010000FF004000A5")

    def test_no_color_and_unsupported_dimming_rejected(self):
        with self.assertRaisesRegex(ValueError, "No remembered color"):
            prepare_color("KS03~", None, brightness=50)
        with self.assertRaises(ValueError):
            prepare_color("KS03-", None, rgb=[255, 0, 0], brightness=50)


class ControlsTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "state.json"
        self.output = io.StringIO()
        out = contextlib.redirect_stdout(self.output)
        out.__enter__()
        self.addCleanup(out.__exit__, None, None, None)
        self.scan = AsyncMock(return_value=[])
        self.send = AsyncMock()
        for target, name, mock in ((cli.BleakScanner, "discover", self.scan),
                                   (cli, "write_sequence", self.send)):
            p = patch.object(target, name, mock)
            p.start()
            self.addCleanup(p.stop)

    async def run_rgb(self):
        await cli.main(["rgb", "--address", "one", "--rgb", "255", "0", "0",
                        "--brightness", "64", "--state-file", str(self.path), "--json"])

    async def test_cli_color_then_dimming_after_reload(self):
        await self.run_rgb()
        self.assertEqual(json.loads(self.output.getvalue())["confirmation"], "unconfirmed")
        await cli.main(["brightness", "--address", "one", "--brightness", "32",
                        "--state-file", str(self.path)])
        self.assertEqual(self.send.await_args.args[3][-1].hex().upper(), "5A0001FF0000002000A5")
        self.assertEqual(StateStore(self.path).get("one", "KS03~")["brightness"], 32)
        self.scan.assert_not_awaited()

    async def test_failed_send_does_not_save_state(self):
        self.send.side_effect = RuntimeError("offline")
        with self.assertRaises(RuntimeError):
            await self.run_rgb()
        self.assertFalse(self.path.exists())

    async def test_unknown_color_does_not_write(self):
        with self.assertRaisesRegex(SystemExit, "No remembered color"):
            await cli.main(["brightness", "--address", "one", "--brightness", "32",
                            "--state-file", str(self.path)])
        self.send.assert_not_awaited()

    async def test_scan_json_filters_and_deduplicates(self):
        self.scan.return_value = [
            SimpleNamespace(name="KS03~one", address="one"),
            SimpleNamespace(name="KS03~one", address="one"),
            SimpleNamespace(name=None, address="unknown")]
        await cli.main(["scan", "--json"])
        self.assertEqual(len(json.loads(self.output.getvalue())), 1)
        self.send.assert_not_awaited()

    async def test_list_profiles_never_scans(self):
        await cli.main(["list", "--json"])
        self.assertEqual(len(json.loads(self.output.getvalue())), 15)
        self.scan.assert_not_awaited()

    async def test_invalid_color_rejected_before_scan(self):
        with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
            await cli.main(["rgb", "--rgb", "256", "0", "0"])
        self.scan.assert_not_awaited()
        self.send.assert_not_awaited()

    async def test_menu_failed_send_preserves_saved_settings(self):
        StateStore(self.path).put("one", "KS03~", [255, 0, 0], 64)
        with patch.object(menu, "STATE_FILE", self.path), patch.object(menu, "send_command", AsyncMock(return_value=False)):
            self.assertFalse(await menu.apply_rgb(("one", "lamp", "KS03~"), "blue", [0, 0, 255]))
        self.assertEqual(StateStore(self.path).get("one", "KS03~")["rgb"], [255, 0, 0])

    async def test_menu_custom_color_refreshes_presets(self):
        presets = Path(self.temp.name) / "presets.json"
        device = ("one", "lamp", "KS03~")
        with patch.object(menu, "PRESETS_FILE", presets), patch.object(menu, "scan_devices", AsyncMock(return_value=[device])), patch.object(menu, "print_header"), patch.object(menu, "get_input", side_effect=["", "4", "3", "q"]), patch.object(menu, "load_devices", return_value={}):
            async def custom(_):
                menu.save_presets({"new": {"r": 1, "g": 2, "b": 3}})
            with patch.object(menu, "custom_color_menu", custom), patch.object(menu, "color_preset_menu", AsyncMock()) as display:
                await menu.main()
                self.assertIn("new", display.await_args.args[1])
