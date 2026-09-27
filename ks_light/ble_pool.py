"""Small hub-owned BLE session cache; a failed command is never replayed."""
import asyncio
import logging
import time
from dataclasses import dataclass

from bleak import BleakClient
from .transport import UUID_TEMPLATE

LOG = logging.getLogger(__name__)


@dataclass
class Session:
    client: object
    service: str
    characteristic_id: str
    characteristic: object = None
    response: bool = False
    active: bool = True
    touched: float = 0
    idle_task: object = None


class BleSessionPool:
    def __init__(self, *, client_factory=None, idle_seconds=30, max_sessions=2,
                 timeout=10, settle_delay=.3, command_delay=.1, final_delay=.1):
        self.factory = client_factory or BleakClient
        self.idle_seconds, self.max_sessions, self.timeout = idle_seconds, max_sessions, timeout
        self.settle_delay, self.command_delay, self.final_delay = settle_delay, command_delay, final_delay
        self.sessions = {}
        self.guard = asyncio.Lock()
        self.closed = False

    async def disconnect(self, session):
        try:
            await asyncio.wait_for(session.client.disconnect(), 3)
        except Exception:
            # Exception text may contain device identifiers.
            LOG.warning("BLE session cleanup failed")

    async def expire(self, address, session):
        await asyncio.sleep(self.idle_seconds)
        async with self.guard:
            if self.sessions.get(address) is session and not session.active:
                del self.sessions[address]
                await self.disconnect(session)

    async def write(self, address, service, characteristic, packets):
        packets = tuple(packets)
        if not packets or any(not isinstance(p, bytes) or not p for p in packets):
            raise ValueError("Nonempty byte packets required")
        async with self.guard:
            if self.closed:
                raise RuntimeError("BLE pool closed")
            session = self.sessions.get(address)
            if session and session.active:
                raise RuntimeError("Concurrent ownership of one light")
            if session:
                session.idle_task.cancel()
                if (not session.client.is_connected or session.service != service or session.characteristic_id != characteristic):
                    del self.sessions[address]
                    await self.disconnect(session)
                    session = None
            if session is None:
                if len(self.sessions) >= self.max_sessions:
                    idle = [(key, value) for key, value in self.sessions.items() if not value.active]
                    if not idle:
                        raise RuntimeError("BLE pool busy")
                    key, old = min(idle, key=lambda pair: pair[1].touched)
                    del self.sessions[key];old.idle_task.cancel()
                    await self.disconnect(old)
                session = Session(self.factory(address), service, characteristic)
                self.sessions[address] = session
            session.active = True

        async def send():
            if session.characteristic is None:
                await session.client.connect()
                if not session.client.is_connected:
                    raise RuntimeError("BLE connection failed")
                target_service = session.client.services.get_service(UUID_TEMPLATE % service.lower())
                char = target_service.get_characteristic(UUID_TEMPLATE % characteristic.lower()) if target_service else None
                if char is None or not ({"write", "write-without-response"} & set(char.properties)):
                    raise RuntimeError("Configured characteristic unavailable")
                session.characteristic = char
                session.response = "write-without-response" not in char.properties
                await asyncio.sleep(self.settle_delay)
            for index, packet in enumerate(packets):
                await session.client.write_gatt_char(session.characteristic, packet, response=session.response)
                if index < len(packets)-1:
                    await asyncio.sleep(self.command_delay)
            await asyncio.sleep(self.final_delay)

        success = False
        try:
            await asyncio.wait_for(send(), self.timeout)
            success = True
        finally:
            async with self.guard:
                session.active = False
                if success and not self.closed:
                    session.touched = time.monotonic()
                    session.idle_task = asyncio.create_task(self.expire(address, session))
                else:
                    self.sessions.pop(address, None)
                    await self.disconnect(session)

    async def close(self):
        async with self.guard:
            self.closed = True
            sessions = list(self.sessions.values());self.sessions.clear()
            for session in sessions:
                if session.idle_task:
                    session.idle_task.cancel()
            await asyncio.gather(*(self.disconnect(session) for session in sessions))
