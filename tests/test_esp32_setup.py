import json
import unittest

from ks_light.esp32_setup import exchange, setup_packet


class SetupTests(unittest.TestCase):
    def settings(self):
        return {"wifi_ssid": "Desk", "wifi_password": "private password", "hub_origin": "https://hub.test:8443",
                "hub_token": "t" * 32, "light_id": "desk", "ntp_host": "time.test",
                "hub_ca": "-----BEGIN CERTIFICATE-----\nexample\n-----END CERTIFICATE-----"}

    def test_bounded_roundtrip_and_rejected_fields(self):
        settings = self.settings()
        packet = setup_packet("configure", settings)
        self.assertEqual(json.loads(packet)["settings"], settings)
        self.assertEqual(packet.count(b"\n"), 1)
        for key, value in (("hub_origin", "http://hub.test"), ("hub_origin", "https://hub.test/api/v1"),
                           ("hub_token", "short"), ("light_id", "../other"), ("hub_ca", "a" * 5000),
                           ("wifi_ssid", "a\0b"), ("wifi_ssid", "é" * 17)):
            with self.subTest(key=key, value=value[:30]), self.assertRaises(ValueError):
                setup_packet("configure", {**settings, key: value})
        with self.assertRaises(ValueError):
            setup_packet("configure", {**settings, "unexpected": "x"})

    def test_single_submission_and_private_logs_not_relayed(self):
        class Port:
            writes = []
            lines = iter([b"private arbitrary device log\n", b"KS_SETUP token-secret\n", b"KS_SETUP saved\n"])
            def write(self, value):
                self.writes.append(value)
                return len(value)
            def flush(self): pass
            def read_until(self, *args): return next(self.lines)
        port = Port()
        self.assertEqual(exchange(port, setup_packet("status")), "saved")
        self.assertEqual(len(port.writes), 1)

    def test_incomplete_write_is_not_replayed(self):
        class Port:
            writes = 0
            def write(self, value):
                self.writes += 1
                return len(value) - 1
        port = Port()
        with self.assertRaises(OSError):
            exchange(port, setup_packet("forget"))
        self.assertEqual(port.writes, 1)
