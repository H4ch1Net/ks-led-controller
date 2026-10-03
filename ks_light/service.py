"""Run a configured hub in the foreground for an OS service manager."""
import argparse
import asyncio
import json
import ipaddress
import ssl
import logging
from logging.handlers import RotatingFileHandler
from pathlib import Path
import sys

from aiohttp import web
from .api_errors import integer
from .hub import create_app, validate_lights
from .mqtt_bridge import topic_id
from .hub_library import load_library


def load_config(filename):
    path = Path(filename).resolve()
    data = json.loads(path.read_text(encoding="utf-8-sig"))
    required = {"version", "mode", "port", "lights_file", "token_file", "runtime_dir"}
    if not isinstance(data, dict) or not required <= set(data) or set(data) - required - {"mqtt", "listen_host", "tls", "persist_state", "library_file", "credentials_file", "dashboard"}:
        raise ValueError("Invalid service configuration fields")
    if type(data["version"]) is not int or data["version"] != 1:
        raise ValueError("Unsupported service configuration version")
    if data["mode"] not in ("simulation", "ble") or not integer(data["port"], 1, 65535):
        raise ValueError("Invalid mode or port")

    def resolve(value):
        if not isinstance(value, str) or not value.strip():
            raise ValueError("Expected a nonempty file path")
        return (path.parent / value).resolve()

    def secret(value):
        content = resolve(value).read_text(encoding="utf-8-sig").rstrip("\r\n")
        if not content or "\n" in content or "\r" in content:
            raise ValueError("Secret files must contain one nonempty line")
        return content

    host = data.get("listen_host", "127.0.0.1")
    if not isinstance(host, str):
        raise ValueError("Listen host must be an IP address")
    address = ipaddress.ip_address(host)
    if not address.is_loopback and "tls" not in data:
        raise ValueError("Non-loopback listeners require TLS")
    ssl_context = None
    if "tls" in data:
        tls = data["tls"]
        if not isinstance(tls, dict) or set(tls) != {"cert_file", "key_file"}:
            raise ValueError("TLS requires certificate and key files")
        ssl_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        ssl_context.minimum_version = ssl.TLSVersion.TLSv1_2
        ssl_context.load_cert_chain(str(resolve(tls["cert_file"])), str(resolve(tls["key_file"])), password=lambda: "")

    catalog = json.loads(resolve(data["lights_file"]).read_text(encoding="utf-8-sig"))
    if not isinstance(catalog, dict) or set(catalog) != {"lights"}:
        raise ValueError("Invalid light catalog")
    validate_lights(catalog["lights"])
    token = secret(data["token_file"])
    if len(token) < 32 or not token.isascii() or any(c.isspace() for c in token):
        raise ValueError("Invalid API token; require at least 32 non-whitespace ASCII characters")
    runtime = resolve(data["runtime_dir"])
    if type(data.get("persist_state", False)) is not bool:
        raise ValueError("persist_state must be boolean")
    if type(data.get("dashboard", True)) is not bool:
        raise ValueError("dashboard must be boolean")
    mqtt = None
    if "mqtt" in data:
        raw = data["mqtt"]
        if (not isinstance(raw, dict) or not {"hostname", "hub_id"} <= set(raw)
                or set(raw) - {"hostname", "hub_id", "port", "tls", "ca_file", "username", "password_file"}):
            raise ValueError("Invalid MQTT configuration fields")
        if not isinstance(raw["hostname"], str) or not raw["hostname"].strip():
            raise ValueError("Invalid broker hostname")
        if not integer(raw.get("port", 1883), 1, 65535) or type(raw.get("tls", False)) is not bool:
            raise ValueError("Invalid MQTT port or TLS setting")
        if "username" in raw and (not isinstance(raw["username"], str) or not raw["username"]):
            raise ValueError("Invalid MQTT username")
        if "password_file" in raw and "username" not in raw:
            raise ValueError("MQTT password requires a username")
        if "ca_file" in raw and not raw.get("tls", False):
            raise ValueError("MQTT CA file requires TLS")
        mqtt = {k: v for k, v in raw.items() if k not in {"password_file", "ca_file"}}
        mqtt["hub_id"] = topic_id(raw["hub_id"])
        mqtt["manifest"] = str(runtime / "discovery.json")
        if "password_file" in raw:
            mqtt["password"] = secret(raw["password_file"])
        if "ca_file" in raw:
            mqtt["ca_file"] = str(resolve(raw["ca_file"]))
    return dict(lights=catalog["lights"], library=load_library(resolve(data["library_file"])) if "library_file" in data else None, token=token, simulation=data["mode"] == "simulation",
                port=data["port"], runtime=runtime, state_file=runtime / "last-sent.json" if data.get("persist_state", False) else None, mqtt=mqtt, host=host, ssl_context=ssl_context,
                credentials_file=resolve(data['credentials_file']) if 'credentials_file' in data else None,
                library_file=resolve(data['library_file']) if 'library_file' in data else None,
                lights_file=resolve(data['lights_file']), dashboard=data.get("dashboard", True))


class InstanceLock:
    """OS-held lock; releases on exit/crash without stale PID-file recovery."""
    def __init__(self, path):
        self.path, self.handle = Path(path), None

    def __enter__(self):
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.handle = self.path.open("a+b")
        try:
            if sys.platform == "win32":
                import msvcrt
                self.handle.seek(0, 2)
                if self.handle.tell() == 0:
                    self.handle.write(b"0"); self.handle.flush()
                self.handle.seek(0)
                msvcrt.locking(self.handle.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(self.handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            self.handle.close()
            raise RuntimeError("Another hub owns this runtime directory") from None
        return self

    def __exit__(self, *args):
        self.handle.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", required=True)
    parser.add_argument("--check", action="store_true", help="Validate without network or BLE access")
    args = parser.parse_args()
    try:
        config = load_config(args.config)
        if config["mqtt"] and sys.platform == "win32":
            asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
        def build_app():
            return create_app(config["lights"], config["token"], simulation=config["simulation"], mqtt=config["mqtt"], state_file=config["state_file"], library=config["library"], credentials_file=config['credentials_file'], library_file=config['library_file'], lights_file=config['lights_file'], dashboard=config['dashboard'])
        if args.check:
            build_app()
            print("Configuration valid; no network connections or light commands sent")
            if config["dashboard"]:
                scheme = "https" if config["ssl_context"] else "http"
                host = f"[{config['host']}]" if ":" in config["host"] else config["host"]
                print(f"Dashboard: {scheme}://{host}:{config['port']}/")
            return
        with InstanceLock(config["runtime"] / "hub.lock"):
            app = build_app()
            handler = RotatingFileHandler(config["runtime"] / "hub.log", maxBytes=1048576, backupCount=3, encoding="utf-8")
            handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
            logging.basicConfig(level=logging.INFO, handlers=[handler])
            logging.getLogger(__name__).info("Hub starting in %s mode", "simulation" if config["simulation"] else "BLE")
            try:
                web.run_app(app, host=config["host"], port=config["port"], ssl_context=config["ssl_context"], access_log=None, print=None)
            finally:
                logging.getLogger(__name__).info("Hub stopped")
                handler.close()
    except (ValueError, TypeError, KeyError, OSError, RuntimeError) as error:
        print(f"Hub setup failed: {describe(error)}", file=sys.stderr)
        raise SystemExit(2)


def describe(error):
    """Explain a setup failure without echoing file contents, which may hold secrets."""
    if isinstance(error, json.JSONDecodeError):
        return f"invalid JSON at line {error.lineno}, column {error.colno}"
    if isinstance(error, ssl.SSLError):
        return "the TLS certificate or key could not be loaded"
    if isinstance(error, UnicodeError):
        return "a configuration file is not valid UTF-8"
    if isinstance(error, OSError):
        return f"{error.strerror or 'file error'}: {error.filename}" if error.filename else (error.strerror or "operating system error")
    if isinstance(error, (ValueError, RuntimeError)):
        return str(error)
    return "check configuration, secret files, runtime ownership and port availability"


if __name__ == "__main__":
    main()
