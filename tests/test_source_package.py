import io
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace
import zipfile

from ks_light.source_package import check_inventory, create, verify


class SourcePackageTests(unittest.TestCase):
    def test_new_source_requires_inventory_review(self):
        with patch('ks_light.source_package.subprocess.run', return_value=SimpleNamespace(stdout=b'old.py\0new.py\0')):
            with self.assertRaisesRegex(ValueError, 'Review'):
                check_inventory(Path('.'), ['old.py'])
            check_inventory(Path('.'), ['old.py', 'new.py'])
    def test_same_bytes_despite_checkout_order_line_endings_and_timestamps(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "code.py").write_bytes(b"one\r\ntwo\r\n")
            (root / "run.bat").write_bytes(b"@echo off\n")
            first, manifest = create(root, ["run.bat", "code.py"])
            (root / "code.py").write_bytes(b"one\ntwo\n")
            os.utime(root / "code.py", (100000, 100000))
            second, _ = create(root, ["code.py", "run.bat"])
            self.assertEqual(first, second)
            archive = root / "test.zip"
            archive.write_bytes(first)
            self.assertEqual(verify(archive), manifest)

    def test_private_traversal_and_case_collisions_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ("../secret", "C:/secret", "key.properties", "apps/esp32/connection.private.json", "x/node_modules/file.js"):
                with self.subTest(name=name), self.assertRaises(ValueError):
                    create(root, [name])
            with self.assertRaises(ValueError):
                create(root, ["code.py", "CODE.py"])

    def test_tampering_fails_without_extracting(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "code.py").write_text("original", encoding="utf-8")
            payload, _ = create(root, ["code.py"])
            archive = root / "tampered.zip"
            with zipfile.ZipFile(io.BytesIO(payload)) as source, zipfile.ZipFile(archive, "w") as changed:
                for entry in source.infolist():
                    changed.writestr(entry, b"changed" if entry.filename == "code.py" else source.read(entry))
            with self.assertRaisesRegex(ValueError, "manifest"):
                verify(archive)
