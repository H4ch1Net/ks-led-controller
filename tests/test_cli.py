"""Regression tests: no real Bluetooth operations or physical lights."""
import contextlib
import io
import unittest
from types import SimpleNamespace
from unittest.mock import AsyncMock, patch

import led_control as cli


class CliTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)
        self.scan = AsyncMock(return_value=[])
        self.write = AsyncMock()
        scan_patch = patch.object(cli.BleakScanner, "discover", self.scan)
        write_patch = patch.object(cli, "write_command", self.write)
        scan_patch.start()
        write_patch.start()
        self.addCleanup(scan_patch.stop)
        self.addCleanup(write_patch.stop)

    async def test_missing_address_scans_and_uses_matching_device(self):
        self.scan.return_value = [
            SimpleNamespace(name=None, address="unrelated"),
            SimpleNamespace(name="KS03~test", address="chosen"),
        ]
        await cli.main(["on", "KS03~"])
        self.scan.assert_awaited_once_with(timeout=8.0)
        self.write.assert_awaited_once_with(
            "chosen", "AFD0", "AFD1", bytes.fromhex("5BF001B5"), verbose=False
        )

    async def test_explicit_address_skips_scan(self):
        await cli.main(["off", "KS03~", "--address", "chosen"])
        self.scan.assert_not_awaited()
        self.assertEqual(self.write.await_args.args[3], bytes.fromhex("5B0F01B5"))

    async def test_no_match_fails_without_writing(self):
        with self.assertRaisesRegex(SystemExit, "No device found"):
            await cli.main(["on"])
        self.write.assert_not_awaited()

    async def test_multiple_matches_require_selection(self):
        self.scan.return_value = [
            SimpleNamespace(name="KS03~one", address="one"),
            SimpleNamespace(name="KS03~two", address="two"),
        ]
        with self.assertRaisesRegex(SystemExit, "--address"):
            await cli.main(["on"])
        self.write.assert_not_awaited()

    async def test_duplicate_advertisements_are_one_target(self):
        self.scan.return_value = [
            SimpleNamespace(name="KS03~one", address="one"),
            SimpleNamespace(name="KS03~one", address="one"),
        ]
        await cli.main(["on"])
        self.write.assert_awaited_once()

    async def test_bulk_partial_failure_attempts_other_targets_and_fails(self):
        self.scan.return_value = [
            SimpleNamespace(name="KS03~one", address="one"),
            SimpleNamespace(name="KS03-two", address="two"),
        ]
        self.write.side_effect = [RuntimeError("disconnected"), None]
        with self.assertRaises(SystemExit) as result:
            await cli.main(["on", "--all-ks03"])
        self.assertEqual(result.exception.code, 1)
        self.assertEqual(self.write.await_count, 2)
        self.assertEqual(self.write.await_args_list[1].args[1:3], ("FFF0", "FFF3"))

    async def test_bulk_success_returns_normally(self):
        self.scan.return_value = [SimpleNamespace(name="KS03~one", address="one")]
        await cli.main(["on", "--all-ks03"])
        self.write.assert_awaited_once()

    async def test_invalid_timeouts_rejected_before_scan(self):
        for timeout in ("0", "-1", "nan", "inf"):
            with self.subTest(timeout=timeout), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as result:
                    await cli.main(["on", "--timeout", timeout])
                self.assertEqual(result.exception.code, 2)
        self.scan.assert_not_awaited()
        self.write.assert_not_awaited()


if __name__ == "__main__":
    unittest.main()
