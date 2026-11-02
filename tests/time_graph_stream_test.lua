local Stream = require("src/core/time_graph_stream")

local function expect(actual, expected, message)
    assert(actual == expected, message .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local graph = Stream.new({ metric = "gold", interval = 1, capacity = 3 })
graph:Advance(100)
graph:Push(10)
graph:Advance(149)
graph:Push(-3)
expect(graph:GetBucket(1), 7, "same-interval signed deltas aggregate")
graph:Advance(150)
graph:Push(4)
local first = graph:GetSnapshot()
expect(first.buckets[1].complete, true, "exact boundary closes previous bucket")
expect(first.buckets[2].value, 4, "boundary update enters next bucket")
expect(first.buckets[2].startSeconds, 1, "new bucket timestamp")
expect(first.buckets[2].complete, false, "current bucket remains live")
first.buckets[2].value = 999
expect(graph:GetBucket(2), 4, "snapshot mutation cannot corrupt stream")
graph:Advance(250)
local rolled = graph:GetSnapshot()
expect(#rolled.buckets, 3, "retention is bounded")
expect(rolled.buckets[1].value, 4, "oldest bucket evicted chronologically")
expect(rolled.buckets[2].value, 0, "idle interval retained")
expect(rolled.buckets[3].startSeconds, 3, "current timestamp after gap")
expect(rolled.total, 11, "session total survives eviction")
graph:Advance(1000250)
expect(graph:GetBucket(1), 0, "long idle gap expires history")
expect(graph.count, 3, "long gap remains bounded")
expect(graph.total, 11, "long gap preserves session total")
local elapsed = graph.elapsedTicks
graph:Advance(1000250)
graph:Advance(90)
expect(graph.elapsedTicks, elapsed, "duplicate and stale ticks never rewind time")
graph:Reset()
expect(graph.total, 0, "reset clears session")
expect(graph.count, 1, "reset removes history")
graph:Advance(1000300)
expect(graph:GetSnapshot().buckets[2].startSeconds, 1, "reset restarts interval clock")

for _, invalid in ipairs({ 0 / 0, math.huge, -math.huge, "12" }) do
    expect(graph:Push(invalid), false, "nonfinite and nonnumeric values rejected")
end
expect(graph.total, 0, "invalid values do not corrupt totals")
local huge = Stream.new({ metric = "huge" })
huge:Push(1e308)
expect(huge:Push(1e308), false, "overflow rejected atomically")
expect(huge.total, 1e308, "overflow preserves previous total")
local integer = Stream.new({ metric = "integer" })
integer:Push(math.maxinteger)
integer:Push(math.maxinteger)
assert(integer.total > math.maxinteger, "integer totals must not wrap negative")
for _, options in ipairs({
    { metric = "" }, { metric = "x", interval = 0 }, { metric = "x", interval = 0.03 },
    { metric = "x", capacity = 1 }, { metric = "x", capacity = 2.5 },
}) do
    expect(pcall(Stream.new, options), false, "invalid graph options rejected")
end

local bus = Stream.CreateEventBus()
local received = {}
local extra = function(event) received[#received + 1] = "extra:" .. event.value end
local second = function(event) received[#received + 1] = event.metric .. ":" .. event.value end
local firstListener = function(event)
    event.metric, event.value = "corrupted", -999
    bus.Update.Unsubscribe(second)
    bus.Update.Subscribe(extra)
end
bus.Update.Subscribe(firstListener)
bus.Update.Subscribe(second)
bus.Update.Subscribe(second)
bus.Update.Publish({ metric = "xp", value = 25 })
expect(table.concat(received, ","), "xp:25", "publication snapshots subscriptions and isolates payloads")
bus.Update.Publish({ metric = "xp", value = 50 })
expect(table.concat(received, ","), "xp:25,extra:50", "subscription mutations apply next publication")
bus.Update.Unsubscribe(firstListener)
bus.Update.Unsubscribe(extra)
local calls = 0
bus.Update.Subscribe(function() error("consumer failure") end)
bus.Update.Subscribe(function() calls = calls + 1 end)
bus.Update.Publish({ metric = "xp", value = 1 })
expect(calls, 1, "failing subscriber cannot starve next consumer")
for _, payload in ipairs({ {}, { metric = "xp", value = 0 / 0 }, { metric = "xp", value = "1" } }) do
    expect(bus.Update.Publish(payload), false, "invalid update schema rejected")
end
expect(calls, 1, "invalid updates are never delivered")
print("time_graph_stream_test: ok")
