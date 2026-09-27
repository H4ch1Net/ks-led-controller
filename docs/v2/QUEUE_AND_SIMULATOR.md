# Queue and simulator

## Run without Bluetooth

```text
python -m ks_light.simulator
```

This command never loads a BLE client or scans nearby devices. It demonstrates
101 coalesced slider settings, a second working light and an offline light.
Expected totals: 100 superseded, two succeeded, one failed; at most two simultaneous sends.

## Library contract
CommandQueue takes an async sender(target, command). A command is an opaque,
immutable-by-convention description of one transaction, including an entire
power-plus-color sequence when appropriate. The sender owns transport cleanup.
The queue is confined to one asyncio event loop.

submit returns a future containing Result(status, error). Status is succeeded,
failed, cancelled, superseded or rejected. Succeeded describes delivery only.
Independent targets can run concurrently, but each target runs serially.
The default bounds are eight pending commands per target, two concurrent sends
and 64 registered targets. An active transaction is additional to pending capacity.
Targets remain registered for the queue lifetime to preserve generation history.

Use a key only for replaceable absolute settings: slider position or effect frame.
Never coalesce relative increments, toggle commands or distinct transactions.
Coalescing replaces pending entries; it does not interrupt an already active send.
A failed command discards pending work and advances the target generation.
Fresh explicit submissions can retry; old producer frames must not.

## Stopping effects and restoration
Capture generation(target) when a producer starts. Include that generation on
every frame submission. invalidate(target) advances it, cancels pending entries
and requests cancellation of the active sender.
Enqueue restoration with the returned generation. The target worker waits for
sender cancellation/cleanup before sending restoration. Late frames are rejected.
This mechanism cannot reverse a command already delivered to hardware.
The full effect engine and effect ownership UI remain planned.

Closing rejects new work, invalidates queued work and waits for sender cleanup.
The sender must cooperate with cancellation; Python cannot forcibly terminate
an arbitrary coroutine that suppresses cancellation. The BLE sender has its own
operation and disconnect deadlines. The queue timeout applies after acquiring a
global connection slot, not to time spent waiting in the queue.

## Simulator scope
SimulatedTransport tracks last commands and bounded delivery history, and can
model offline or hanging targets. It is not a model of the proprietary packet
protocol, physical color output, radio timing or firmware behavior.
The queue and simulator are library components. Legacy CLI/menu writes still
use the direct sequence transport; hub/effect callers will use the queue.

## Dependencies and CI
Baseline: Python 3.10 or newer; Bleak 3.0.2 pinned as the direct dependency.
Transitive dependencies remain platform-resolved, so this is not a full lockfile.
Configured CI: Windows and Ubuntu, Python 3.10 and 3.12, pip check, tests and demo.
Only Windows/Python 3.10.11 has been executed locally. The GitHub workflow has not
run because these changes are local and have not been pushed.
