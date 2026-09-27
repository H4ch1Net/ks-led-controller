"""Hardware-free transport and runnable queue demonstration."""
import asyncio
from collections import deque
import json

from .queue import CommandQueue


class SimulatedTransport:
    def __init__(self, *, delay=0.01, history_limit=100):
        if delay < 0 or history_limit < 1:
            raise ValueError("Invalid simulator limits")
        self.delay = delay
        self.offline = set()
        self.hung = set()
        self.state = {}
        self.events = deque(maxlen=history_limit)
        self.active = 0
        self.peak = 0

    async def send(self, target, command):
        self.active += 1
        self.peak = max(self.peak, self.active)
        try:
            if target in self.offline:
                raise ConnectionError("simulated_offline")
            if target in self.hung:
                await asyncio.Event().wait()
            await asyncio.sleep(self.delay)
            self.state[target] = command
            self.events.append({"target": target, "command": command})
        finally:
            self.active -= 1


async def demo():
    transport = SimulatedTransport()
    transport.offline.add("offline-lamp")
    async with CommandQueue(transport.send) as queue:
        futures = [queue.submit("desk", {"brightness": value}, key="settings")
                   for value in range(101)]
        futures.append(queue.submit("ceiling", {"power": True}))
        futures.append(queue.submit("offline-lamp", {"power": True}))
        results = await asyncio.gather(*futures)
    counts = {}
    for result in results:
        counts[result.status] = counts.get(result.status, 0) + 1
    print(json.dumps({"mode": "simulation_only", "results": counts,
                      "state": transport.state, "peak_connections": transport.peak,
                      "writes": list(transport.events)}, indent=2))


if __name__ == "__main__":
    asyncio.run(demo())
