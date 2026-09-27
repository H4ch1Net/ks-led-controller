# Local API target contract (partially implemented)
The first working subset is documented in HUB_API.md. This document retains the broader target contract; scopes, pairing, groups/scenes and WebSockets are not implemented yet.
Base path /api/v1. JSON. Brightness is 0..100; RGB components are integer 0..255; durations are milliseconds. Validate at the API boundary and again when encoding packets.
Unauthenticated access is limited to pairing during a locally enabled setup window. Normal requests use a revocable bearer token. Permissions: read, control, configure, admin, optionally restricted to targets.

## Resources
GET /lights; GET /lights/{id}; PATCH /lights/{id}/state
GET /groups; POST /groups; PATCH /groups/{id}; DELETE /groups/{id}
POST /groups/{id}/apply
GET /scenes; POST /scenes; PATCH /scenes/{id}; DELETE /scenes/{id}
POST /scenes/{id}/activate
GET /effects; POST /effects; POST /effects/{id}/start
POST /effect-runs/{id}/stop
GET /operations/{id}
GET /capabilities; GET /health
GET /events (WebSocket upgrade)
Provisioning, export/import and scheduling endpoints will be specified before those milestones.

## State request example
PATCH /api/v1/lights/desk/state
{"power":true,"rgb":[255,120,30],"brightness":35,"transition_ms":500}
Reject unknown fields, invalid ranges and incompatible color modes. Return 422 for unsupported capability without silently sending guessed packets.
Only submitted fields change. Off does not erase saved color. Setting color does not imply power on unless power:true is supplied; adapters must preserve this rule or reject unsupported combinations.

## Operation semantics
A queued command returns HTTP 202:
{"operation_id":"op_example","status":"queued"}
Clients poll or subscribe for completion.
Terminal states: succeeded, partial_failure, failed, cancelled. Each target includes delivery status, error code, retryable flag and confirmation: device or unconfirmed.
Succeeded means the transport accepted all required writes; it is not proof of the physical output without readback.
Missing resources:404; malformed JSON:400; authentication:401; scope:403; conflicting ownership:409; queue/rate limit:429; unavailable service:503.
Use explicit errors such as device_unavailable, unsupported_capability, ownership_conflict, write_failed, timeout and cancelled.
Support Idempotency-Key for mutating commands with a bounded documented retention window. Replay with changed payload returns 409. This avoids duplicate effect runs on client retries.

## Events
{"version":1,"sequence":42,"type":"light.updated","target_id":"desk","operation_id":"op_example","timestamp":"...","data":{}}
Events include light.updated, light.availability, operation.updated, effect.started and effect.stopped.
Use a bounded event history and sequence cursor; if a cursor expires, signal resync_required and fetch a fresh snapshot. Do not pretend events have guaranteed infinite retention.
Throttle high-frequency updates; immediately deliver operation errors and effect-stop events.

## Client behavior
Clients use internal IDs rather than MAC addresses. Display requested versus confirmed state distinctly.
Dials send coalesced absolute values or a serialized adjust action, never concurrent read-modify-write loops across clients. The adjust action contract will be finalized with controller implementation.
A first server implementation exists in ks_light/hub.py; see HUB_API.md for exact supported routes and limitations. The SDK and full target contract remain planned.
