"""Bounded BLE writes using only the configured service and characteristic."""
import asyncio
import logging
import math

from bleak import BleakClient

LOG = logging.getLogger(__name__)
UUID_TEMPLATE = "0000%s-0000-1000-8000-00805f9b34fb"


async def write_sequence(address, service_short, char_short, payloads, *,
                         timeout=10.0, disconnect_timeout=3.0,
                         settle_delay=0.3, command_delay=0.5, final_delay=0.2,
                         client_factory=None):
    """Send a finite sequence on one connection; return after delivery, not readback.

    Only advertised write modes are attempted. A timeout/cancellation never
    retries a possibly delivered packet. Cleanup has a separate bounded deadline.
    """
    for value in (timeout, disconnect_timeout):
        if not math.isfinite(value) or value <= 0:
            raise ValueError("Timeouts must be finite and positive")
    for value in (settle_delay, command_delay, final_delay):
        if not math.isfinite(value) or value < 0:
            raise ValueError("Delays must be finite and nonnegative")
    payloads = tuple(payloads)
    if not payloads or any(not isinstance(p, bytes) or not p for p in payloads):
        raise ValueError("Provide nonempty bytes payloads")
    client = (client_factory or BleakClient)(address)

    async def send():
        await client.connect()
        if not client.is_connected:
            raise RuntimeError("Failed to connect")
        service = client.services.get_service(UUID_TEMPLATE % service_short.lower())
        if service is None:
            raise RuntimeError("Configured GATT service not found")
        characteristic = service.get_characteristic(UUID_TEMPLATE % char_short.lower())
        if characteristic is None:
            raise RuntimeError("Configured GATT characteristic not found")
        modes = []
        if "write-without-response" in characteristic.properties:
            modes.append(False)
        if "write" in characteristic.properties:
            modes.append(True)
        if not modes:
            raise RuntimeError("Configured characteristic is not writable")
        await asyncio.sleep(settle_delay)
        for index, payload in enumerate(payloads):
            for mode_index, response in enumerate(modes):
                try:
                    await client.write_gatt_char(characteristic, payload, response=response)
                    break
                except (asyncio.TimeoutError, asyncio.CancelledError):
                    raise
                except Exception:
                    if mode_index == len(modes) - 1:
                        raise
            if index < len(payloads) - 1:
                await asyncio.sleep(command_delay)
        await asyncio.sleep(final_delay)

    try:
        await asyncio.wait_for(send(), timeout)
    finally:
        # Also clean up a partially completed connect. Preserve the original error.
        try:
            await asyncio.wait_for(client.disconnect(), disconnect_timeout)
        except Exception:
            LOG.warning("BLE disconnect failed", exc_info=True)
