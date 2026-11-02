local Stream = {}
Stream.__index = Stream

local TICKS_PER_SECOND = 50

local function finite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

-- Producers publish deltas, not cumulative totals. Values use the units chosen
-- by the producer; negative values are valid (for example net gold loss).
-- Publish is synchronous. Subscription changes affect the next publication;
-- each listener gets its own payload so it cannot change another graph's data.
function Stream.CreateEventBus()
    local listeners = {}
    local update = {}

    function update.Subscribe(callback)
        if type(callback) ~= "function" then return false, "A callback function is required." end
        for _, listener in ipairs(listeners) do
            if listener == callback then return true end
        end
        listeners[#listeners + 1] = callback
        return true
    end

    function update.Unsubscribe(callback)
        for index, listener in ipairs(listeners) do
            if listener == callback then
                table.remove(listeners, index)
                return true
            end
        end
        return false
    end

    function update.Publish(payload)
        if type(payload) ~= "table" or type(payload.metric) ~= "string" or payload.metric == "" then
            return false, "TimeGraph updates require a nonempty metric string."
        end
        if not finite(payload.value) then return false, "TimeGraph updates require a finite numeric delta." end
        local metric, value = payload.metric, payload.value
        local snapshot = {}
        for index, callback in ipairs(listeners) do snapshot[index] = callback end
        for _, callback in ipairs(snapshot) do
            local ok, message = pcall(callback, { metric = metric, value = value })
            if not ok then
                pcall(function()
                    log("[prettyui] TimeGraph update subscriber failed: " .. tostring(message))
                end)
            end
        end
        return true
    end

    return { Update = update }
end

function Stream.new(options)
    options = options or {}
    if type(options.metric) ~= "string" or options.metric == "" then
        error("TimeGraph metric ID must be a nonempty string")
    end
    local interval = options.interval == nil and 5 or options.interval
    if not finite(interval) or interval < 1 / TICKS_PER_SECOND then
        error("TimeGraph interval must be at least 0.02 seconds")
    end
    local ticks = math.floor(interval * TICKS_PER_SECOND + 0.5)
    if not finite(ticks) or math.abs(ticks / TICKS_PER_SECOND - interval) > 0.000001 then
        error("TimeGraph interval must be a multiple of 0.02 seconds")
    end
    local capacity = options.capacity == nil and 60 or options.capacity
    if not finite(capacity) or capacity < 2 or capacity ~= math.floor(capacity) then
        error("TimeGraph capacity must be an integer of at least 2")
    end
    local self = setmetatable({
        metric = options.metric,
        interval = ticks / TICKS_PER_SECOND,
        intervalTicks = ticks,
        capacity = capacity,
        revision = 0,
        values = {},
    }, Stream)
    self:Reset()
    return self
end

function Stream:Reset()
    self.head = 1
    self.count = 1
    self.elapsedTicks = 0
    self.total = 0
    for index = 1, self.capacity do self.values[index] = 0 end
    self.revision = self.revision + 1
end

function Stream:Advance(logicTick)
    if not finite(logicTick) or logicTick < 0 or logicTick ~= math.floor(logicTick) then return false end
    if self.lastTick == nil then
        self.lastTick = logicTick
        return false
    end
    if logicTick <= self.lastTick then return false end
    local previousBucket = math.floor(self.elapsedTicks / self.intervalTicks)
    self.elapsedTicks = self.elapsedTicks + (logicTick - self.lastTick)
    self.lastTick = logicTick
    local steps = math.floor(self.elapsedTicks / self.intervalTicks) - previousBucket
    if steps == 0 then return false end

    -- A suspended client can skip hours: clear at most capacity slots rather
    -- than constructing every expired interval. Total remains session-wide.
    if steps >= self.capacity then
        for index = 1, self.capacity do self.values[index] = 0 end
        self.head = 1
        self.count = self.capacity
    else
        for _ = 1, steps do
            if self.count < self.capacity then
                self.count = self.count + 1
            else
                self.head = self.head % self.capacity + 1
            end
            local slot = (self.head + self.count - 2) % self.capacity + 1
            self.values[slot] = 0
        end
    end
    self.revision = self.revision + 1
    return true
end

function Stream:Push(value)
    if not finite(value) then return false, "TimeGraph values must be finite numeric deltas." end
    -- Force floating-point addition rather than wrapping a Lua integer sum.
    local slot = (self.head + self.count - 2) % self.capacity + 1
    local bucketValue = self.values[slot] + (value + 0.0)
    local total = self.total + (value + 0.0)
    if not finite(bucketValue) or not finite(total) then return false, "TimeGraph value overflow." end
    if value == 0 then return true end
    self.values[slot] = bucketValue
    self.total = total
    self.revision = self.revision + 1
    return true
end

function Stream:GetBucket(index)
    if not finite(index) or index < 1 or index > self.count or index ~= math.floor(index) then return nil end
    local slot = (self.head + index - 2) % self.capacity + 1
    local bucket = math.floor(self.elapsedTicks / self.intervalTicks) - self.count + index
    local startSeconds = bucket * self.interval
    return self.values[slot], startSeconds, startSeconds + self.interval, index < self.count
end

-- Returned data is detached: callers cannot mutate the graph through snapshots.
function Stream:GetSnapshot()
    local buckets = {}
    for index = 1, self.count do
        local value, startSeconds, endSeconds, complete = self:GetBucket(index)
        buckets[index] = { value = value, startSeconds = startSeconds, endSeconds = endSeconds, complete = complete }
    end
    return {
        metric = self.metric,
        interval = self.interval,
        capacity = self.capacity,
        total = self.total,
        elapsedSeconds = self.elapsedTicks / TICKS_PER_SECOND,
        buckets = buckets,
    }
end

return Stream
