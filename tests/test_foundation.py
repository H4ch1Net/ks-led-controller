import asyncio
import contextlib
import io
import json
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock, patch

from ks_light import protocol
from ks_light.profiles import DEVICE_MAPPINGS, DEVICE_UUIDS
from ks_light.transport import write_sequence
import led_menu
import led_control


class ProtocolTests(unittest.TestCase):
    def test_golden_packets(self):
        fixtures = json.loads((Path(__file__).parents[1] / "protocol/golden_packets.json").read_text())
        for item in fixtures:
            with self.subTest(item=item["name"]):
                self.assertEqual(getattr(protocol, item["encoder"])(*item["args"]).hex().upper(), item["hex"])

    def test_invalid_channel_values(self):
        for value in (-1, 256, True, 1.5, "1", None):
            for index in range(4):
                args = [0, 0, 0, "floor", 255]
                args[index if index < 3 else 4] = value
                with self.subTest(value=value, index=index), self.assertRaises(ValueError):
                    protocol.color(*args)
            with self.assertRaises(ValueError):
                protocol.white_brightness(value)

    def test_unsupported_formats_and_brightness(self):
        with self.assertRaises(ValueError):
            protocol.color(1, 2, 3, "unknown")
        with self.assertRaises(ValueError):
            protocol.color(1, 2, 3, "ceiling", 20)
        with self.assertRaises(ValueError):
            protocol.power(1)

    def test_registry_does_not_promote_experimental_color_support(self):
        self.assertEqual(len(DEVICE_UUIDS), 15)
        self.assertEqual(len(DEVICE_MAPPINGS), 5)
        self.assertNotIn("KS15~", DEVICE_MAPPINGS)
        self.assertIs(led_control.DEVICE_UUIDS, DEVICE_UUIDS)
        self.assertIs(led_menu.DEVICE_MAPPINGS, DEVICE_MAPPINGS)


class TransportTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.characteristic = SimpleNamespace(properties=["write-without-response", "write"])
        self.service = Mock()
        self.service.get_characteristic.return_value = self.characteristic
        self.client = SimpleNamespace(
            connect=AsyncMock(), disconnect=AsyncMock(), is_connected=True,
            write_gatt_char=AsyncMock(), services=Mock())
        self.client.services.get_service.return_value = self.service

    async def send(self, **kwargs):
        await write_sequence("device", "AFD0", "AFD1", [b"on", b"color"],
                             client_factory=lambda _: self.client,
                             settle_delay=0, command_delay=0, final_delay=0, **kwargs)

    async def test_sequence_uses_one_connection_and_configured_service(self):
        await self.send()
        self.client.connect.assert_awaited_once()
        self.client.disconnect.assert_awaited_once()
        self.client.services.get_service.assert_called_once_with("0000afd0-0000-1000-8000-00805f9b34fb")
        self.assertEqual([c.args[1] for c in self.client.write_gatt_char.await_args_list], [b"on", b"color"])
        self.assertIs(self.client.write_gatt_char.await_args.args[0], self.characteristic)

    async def test_only_advertised_response_mode(self):
        self.characteristic.properties = ["write"]
        await self.send()
        self.assertTrue(all(c.kwargs["response"] for c in self.client.write_gatt_char.await_args_list))

    async def test_fallback_only_to_advertised_mode(self):
        self.client.write_gatt_char.side_effect = [RuntimeError("rejected"), None, None]
        await self.send()
        self.assertEqual([c.kwargs["response"] for c in self.client.write_gatt_char.await_args_list], [False, True, False])

    async def test_no_fallback_to_unadvertised_mode(self):
        self.characteristic.properties = ["write-without-response"]
        self.client.write_gatt_char.side_effect = RuntimeError("rejected")
        with self.assertRaises(RuntimeError):
            await self.send()
        self.client.write_gatt_char.assert_awaited_once()
        self.client.disconnect.assert_awaited_once()

    async def test_missing_or_read_only_characteristic_never_writes(self):
        for kind in ("service", "characteristic", "read"):
            with self.subTest(kind=kind):
                self.client.services.get_service.return_value = self.service if kind != "service" else None
                self.service.get_characteristic.return_value = self.characteristic if kind != "characteristic" else None
                self.characteristic.properties = ["read"]
                with self.assertRaises(RuntimeError):
                    await self.send()
        self.client.write_gatt_char.assert_not_awaited()
        self.assertEqual(self.client.disconnect.await_count, 3)

    async def test_write_timeout_does_not_retry(self):
        self.client.write_gatt_char.side_effect = asyncio.TimeoutError()
        with self.assertRaises(asyncio.TimeoutError):
            await self.send()
        self.client.write_gatt_char.assert_awaited_once()
        self.client.disconnect.assert_awaited_once()

    async def test_hanging_connect_is_bounded_and_cleaned_up(self):
        async def hang():
            await asyncio.Event().wait()
        self.client.connect.side_effect = hang
        with self.assertRaises(asyncio.TimeoutError):
            await self.send(timeout=0.02)
        self.client.disconnect.assert_awaited_once()

    async def test_cancelled_write_disconnects(self):
        entered = asyncio.Event()
        async def hang(*args, **kwargs):
            entered.set()
            await asyncio.Event().wait()
        self.client.write_gatt_char.side_effect = hang
        task = asyncio.create_task(self.send())
        await asyncio.wait_for(entered.wait(), 1)
        task.cancel()
        with self.assertRaises(asyncio.CancelledError):
            await task
        self.client.disconnect.assert_awaited_once()

    async def test_cleanup_failure_preserves_write_error(self):
        self.client.write_gatt_char.side_effect = ValueError("original")
        self.client.disconnect.side_effect = RuntimeError("cleanup")
        with self.assertLogs("ks_light.transport", "WARNING"), self.assertRaisesRegex(ValueError, "original"):
            await self.send()

    async def test_disconnect_timeout_is_bounded(self):
        async def hang():
            await asyncio.Event().wait()
        self.client.disconnect.side_effect = hang
        with self.assertLogs("ks_light.transport", "WARNING"):
            await asyncio.wait_for(self.send(disconnect_timeout=0.02), 1)

    async def test_invalid_payload_never_connects(self):
        with self.assertRaises(ValueError):
            await write_sequence("device", "AFD0", "AFD1", [b""],
                                 client_factory=lambda _: self.client)
        self.client.connect.assert_not_awaited()

    async def test_menu_color_uses_shared_sequence(self):
        with patch.object(led_menu, "write_sequence", new_callable=AsyncMock) as send, contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(await led_menu.send_command(("address", "name", "KS03~"), b"color", "red", True))
        send.assert_awaited_once_with("address", "AFD0", "AFD1", [bytes.fromhex("5BF001B5"), b"color"])

    async def test_menu_failure_is_reported(self):
        with patch.object(led_menu, "write_sequence", new_callable=AsyncMock) as send, contextlib.redirect_stdout(io.StringIO()):
            send.side_effect = RuntimeError("failed")
            self.assertFalse(await led_menu.send_command(("address", "name", "KS03~"), b"color", "red", True))
