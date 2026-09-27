"""Single-event-loop scheduling for a bounded set of light targets."""
import asyncio
from collections import deque
from dataclasses import dataclass
import math


@dataclass(frozen=True)
class Result:
    status: str
    error: str | None = None


@dataclass
class Entry:
    command: object
    key: str | None
    generation: int
    future: asyncio.Future


class CommandQueue:
    """Serialize each light, limit global writes, and discard superseded work.

    sender(target, command) must propagate cancellation after cleaning up.
    Results describe delivery only. This class does not provide device readback.
    """
    def __init__(self, sender, *, max_pending=8, max_connections=2,
                 max_targets=64, timeout=15.0):
        for value in (max_pending, max_connections, max_targets):
            if type(value) is not int or value < 1:
                raise ValueError("Queue limits must be positive integers")
        if not math.isfinite(timeout) or timeout <= 0:
            raise ValueError("Timeout must be positive and finite")
        self.sender = sender
        self.max_pending = max_pending
        self.max_targets = max_targets
        self.timeout = timeout
        self.slots = asyncio.Semaphore(max_connections)
        self.pending = {}
        self.generations = {}
        self.workers = {}
        self.active = {}
        self.cancelling = set()
        self.closed = False

    def generation(self, target):
        return self.generations.get(target, 0)

    @staticmethod
    def finish(entry, status, error=None):
        if not entry.future.done():
            entry.future.set_result(Result(status, error))

    def submit(self, target, command, *, key=None, generation=None):
        if self.closed:
            raise RuntimeError("Queue is closed")
        if not isinstance(target, str) or not target:
            raise ValueError("Target must be a nonempty string")
        future = asyncio.get_running_loop().create_future()
        current = self.generation(target)
        entry = Entry(command, key, current if generation is None else generation, future)
        if entry.generation != current:
            self.finish(entry, "cancelled", "stale_generation")
            return future
        if target not in self.pending:
            if len(self.pending) >= self.max_targets:
                self.finish(entry, "rejected", "target_limit")
                return future
            self.pending[target] = deque()
            self.generations[target] = current
        queue = self.pending[target]
        # Coalesce only pending absolute settings, never the active transaction.
        if key is not None:
            for old in list(queue):
                if old.key == key:
                    queue.remove(old)
                    self.finish(old, "superseded")
        if len(queue) >= self.max_pending:
            self.finish(entry, "rejected", "queue_full")
            return future
        queue.append(entry)
        if target not in self.workers:
            self.workers[target] = asyncio.create_task(self._work(target))
        return future

    def submit_batch(self, commands):
        """Admit one command per target together, or reject without scheduling any.

        This method is synchronous on the owning event loop. Execution remains
        independent per light; admission does not promise physical atomicity.
        """
        if self.closed:
            raise RuntimeError("Queue is closed")
        targets = [target for target, _ in commands]
        if (not targets or any(not isinstance(t, str) or not t for t in targets)
                or len(set(targets)) != len(targets)):
            raise ValueError("Batch needs unique nonempty targets")
        if (len(set(self.pending) | set(targets)) > self.max_targets
                or any(len(self.pending.get(t, ())) >= self.max_pending for t in targets)):
            return None
        return [self.submit(target, command) for target, command in commands]

    def invalidate(self, target):
        """Stop old work before enqueueing restore/manual commands.

        Returns the new generation; late producer frames using the old one
        are refused. Already delivered physical writes cannot be undone.
        """
        if target not in self.pending:
            return self.generation(target)
        self.generations[target] += 1
        self._discard(target, "cancelled", "invalidated")
        task = self.active.get(target)
        if task is not None and not task.done() and target not in self.cancelling:
            self.cancelling.add(target)
            task.cancel()
        return self.generations[target]

    def _discard(self, target, status, error):
        while self.pending[target]:
            self.finish(self.pending[target].popleft(), status, error)

    async def _send(self, target, entry):
        async with self.slots:
            if entry.future.cancelled() or entry.generation != self.generation(target):
                return Result("cancelled")
            await asyncio.wait_for(self.sender(target, entry.command), self.timeout)
            return Result("succeeded")

    async def _work(self, target):
        try:
            while self.pending[target]:
                entry = self.pending[target].popleft()
                if entry.future.cancelled():
                    continue
                task = asyncio.create_task(self._send(target, entry))
                self.active[target] = task
                try:
                    result = await task
                    self.finish(entry, result.status, result.error)
                except asyncio.CancelledError:
                    self.finish(entry, "cancelled")
                except Exception as error:
                    self.finish(entry, "failed", str(error) or type(error).__name__)
                    # Do not replay frames accumulated while the device failed.
                    self.generations[target] += 1
                    self._discard(target, "cancelled", "prior_command_failed")
                finally:
                    self.active.pop(target, None)
                    self.cancelling.discard(target)
        finally:
            self.workers.pop(target, None)

    async def close(self):
        self.closed = True
        for target in self.pending:
            self.invalidate(target)
        await asyncio.gather(*list(self.workers.values()))

    async def __aenter__(self):
        return self

    async def __aexit__(self, *args):
        await self.close()
