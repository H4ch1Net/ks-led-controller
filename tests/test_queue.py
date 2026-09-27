import asyncio
import unittest

from ks_light.queue import CommandQueue
from ks_light.simulator import SimulatedTransport


class QueueTests(unittest.IsolatedAsyncioTestCase):
    async def test_coalescing_keeps_latest_absolute_value(self):
        sim = SimulatedTransport(delay=0)
        async with CommandQueue(sim.send, max_pending=2) as queue:
            futures = [queue.submit("a", value, key="slider") for value in range(100)]
            results = await asyncio.gather(*futures)
        self.assertEqual(sim.state["a"], 99)
        self.assertEqual(len(sim.events), 1)
        self.assertEqual(sum(r.status == "superseded" for r in results), 99)

    async def test_fifo_and_queue_capacity(self):
        sim = SimulatedTransport(delay=0)
        async with CommandQueue(sim.send, max_pending=2) as queue:
            one = queue.submit("a", 1)
            two = queue.submit("a", 2)
            rejected = await queue.submit("a", 3)
            self.assertEqual(rejected.error, "queue_full")
            await asyncio.gather(one, two)
        self.assertEqual([e["command"] for e in sim.events], [1, 2])

    async def test_global_connection_limit(self):
        sim = SimulatedTransport()
        async with CommandQueue(sim.send, max_connections=2) as queue:
            await asyncio.gather(*(queue.submit(str(i), i) for i in range(10)))
        self.assertEqual(sim.peak, 2)
        self.assertEqual(sim.active, 0)

    async def test_same_light_never_overlaps(self):
        sim = SimulatedTransport()
        async with CommandQueue(sim.send, max_connections=4) as queue:
            await asyncio.gather(*(queue.submit("a", i) for i in range(5)))
        self.assertEqual(sim.peak, 1)

    async def test_one_hung_light_does_not_block_another(self):
        sim = SimulatedTransport(delay=0)
        sim.hung.add("a")
        async with CommandQueue(sim.send, timeout=0.05) as queue:
            hung = queue.submit("a", 1)
            healthy = queue.submit("b", 2)
            self.assertEqual((await asyncio.wait_for(healthy, 0.5)).status, "succeeded")
            self.assertEqual((await hung).status, "failed")
        self.assertEqual(sim.active, 0)

    async def test_failure_discards_pending_frames_and_allows_fresh_work(self):
        sim = SimulatedTransport(delay=0)
        sim.offline.add("a")
        async with CommandQueue(sim.send) as queue:
            old_generation = queue.generation("a")
            failed = queue.submit("a", 1)
            stale = queue.submit("a", 2)
            self.assertEqual((await failed).status, "failed")
            self.assertEqual((await stale).error, "prior_command_failed")
            sim.offline.clear()
            self.assertEqual((await queue.submit("a", 3, generation=old_generation)).status, "cancelled")
            self.assertEqual((await queue.submit("a", 4)).status, "succeeded")
        self.assertEqual(sim.state["a"], 4)

    async def test_stop_waits_for_cleanup_before_restore(self):
        entered = asyncio.Event()
        cleanup_started = asyncio.Event()
        release_cleanup = asyncio.Event()
        writes = []

        async def send(target, command):
            if command == "effect":
                entered.set()
                try:
                    await asyncio.Event().wait()
                finally:
                    cleanup_started.set()
                    await release_cleanup.wait()
            else:
                writes.append(command)

        async with CommandQueue(send) as queue:
            epoch = queue.generation("a")
            active = queue.submit("a", "effect", generation=epoch)
            await asyncio.wait_for(entered.wait(), 1)
            pending = queue.submit("a", "old-frame", generation=epoch)
            new_epoch = queue.invalidate("a")
            restore = queue.submit("a", "restore", generation=new_epoch)
            late = queue.submit("a", "late-frame", generation=epoch)
            await asyncio.wait_for(cleanup_started.wait(), 1)
            self.assertFalse(restore.done())
            release_cleanup.set()
            results = await asyncio.wait_for(asyncio.gather(active, pending, restore, late), 1)
        self.assertEqual([r.status for r in results], ["cancelled", "cancelled", "succeeded", "cancelled"])
        self.assertEqual(writes, ["restore"])

    async def test_repeated_stop_does_not_interrupt_cleanup(self):
        entered = asyncio.Event()
        cleaning = asyncio.Event()
        release = asyncio.Event()
        finished = asyncio.Event()
        async def send(target, command):
            entered.set()
            try:
                await asyncio.Event().wait()
            finally:
                cleaning.set()
                await release.wait()
                finished.set()
        queue = CommandQueue(send)
        future = queue.submit("a", 1)
        await asyncio.wait_for(entered.wait(), 1)
        queue.invalidate("a")
        await asyncio.wait_for(cleaning.wait(), 1)
        queue.invalidate("a")
        await asyncio.sleep(0)
        self.assertFalse(future.done())
        release.set()
        await asyncio.wait_for(queue.close(), 1)
        self.assertTrue(finished.is_set())
        self.assertEqual((await future).status, "cancelled")

    async def test_cancel_pending_future_does_not_send(self):
        sim = SimulatedTransport(delay=0)
        async with CommandQueue(sim.send) as queue:
            future = queue.submit("a", 1)
            future.cancel()
            await asyncio.sleep(0)
        self.assertEqual(list(sim.events), [])

    async def test_close_cancels_hanging_work_and_rejects_new_work(self):
        sim = SimulatedTransport()
        sim.hung.add("a")
        queue = CommandQueue(sim.send)
        future = queue.submit("a", 1)
        await asyncio.sleep(0)
        await asyncio.wait_for(queue.close(), 1)
        self.assertEqual((await future).status, "cancelled")
        self.assertEqual(sim.active, 0)
        self.assertEqual(queue.workers, {})
        with self.assertRaises(RuntimeError):
            queue.submit("b", 2)

    async def test_target_count_is_bounded(self):
        sim = SimulatedTransport(delay=0)
        async with CommandQueue(sim.send, max_targets=1) as queue:
            await queue.submit("a", 1)
            self.assertEqual((await queue.submit("b", 2)).error, "target_limit")

    async def test_history_is_bounded(self):
        sim = SimulatedTransport(delay=0, history_limit=2)
        async with CommandQueue(sim.send) as queue:
            for i in range(5):
                await queue.submit("a", i)
        self.assertEqual([e["command"] for e in sim.events], [3, 4])

    def test_limits_are_validated(self):
        for kwargs in ({"max_pending": 0}, {"max_targets": True},
                       {"max_connections": 0}, {"timeout": float("nan")}):
            with self.assertRaises(ValueError):
                CommandQueue(None, **kwargs)
