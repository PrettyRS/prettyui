-- Share loaded interfaces and a complete native namespace across UI doubles.
local Interfaces = {}
local loaded, components, namespaces, registered = {}, {}, {}, {}
local nextStaticID = {}
local wrapped, tracked = setmetatable({}, { __mode = "k" }),
    setmetatable({}, { __mode = "k" })

local function isLive(component)
    while component do
        if component.destroyed then return false end
        component = component.parent
    end
    return true
end

local function getInterface(previous, self, interfaceID)
    assert(type(interfaceID) == "number", "interface lookup requires a cached numeric ID")
    if registered[interfaceID] then return loaded[interfaceID] end
    return previous and previous(self, interfaceID) or nil
end

local function install()
    if not ui then return end
    ui.Interfaces = ui.Interfaces or {}
    local api = ui.Interfaces
    local previous = wrapped[api]
    if previous and previous.get == api.GetComponent and previous.interface == api.GetInterface then
        return
    end
    local previousGet = api.GetComponent
    local previousInterface = api.GetInterface
    local function getComponent(self, first, second, third, fourth)
        if fourth ~= nil then
            local host = namespaces[first] and namespaces[first][second]
            local category = host and host[third]
            local component = category and category[fourth]
            if component and isLive(component) then return component end
            if components[first] ~= nil then return nil end
        elseif second ~= nil and third == nil then
            local host = namespaces[first] and namespaces[first][second]
            if host and host.static and isLive(host.static) then return host.static end
        elseif second == nil then
            local interfaceID = math.floor(first / 65536)
            local staticID = first % 65536
            local host = namespaces[interfaceID] and namespaces[interfaceID][staticID]
            if host and host.static and isLive(host.static) then return host.static end
        end
        return previousGet and previousGet(self, first, second, third, fourth) or nil
    end
    local function interface(self, interfaceID)
        return getInterface(previousInterface, self, interfaceID)
    end
    api.GetInterface, api.GetComponent = interface, getComponent
    wrapped[api] = { get = getComponent, interface = interface }
end

local function addChild(parent, component)
    local children = parent.children or parent.dynamicComponents
    if not children then
        children = {}
        parent.children = children
    end
    if children[#children] == component then return end
    for _, child in ipairs(children) do
        if child == component then return end
    end
    children[#children + 1] = component
end
function Interfaces.component(component, parent, categoryID, dynamicID)
    parent = parent or component.parent
    if parent and parent ~= component and not parent.parentStatic then
        Interfaces.component(parent)
    end
    local interfaceID = component.interfaceID or (parent and parent.interfaceID) or 1
    component.interfaceID = interfaceID
    components[interfaceID] = components[interfaceID] or {}
    registered[interfaceID] = true
    loaded[interfaceID] = loaded[interfaceID] or {}
    namespaces[interfaceID] = namespaces[interfaceID] or {}

    local static = parent and (parent.parentStatic or parent) or component
    if static.staticID == nil then
        nextStaticID[interfaceID] = (nextStaticID[interfaceID] or 0) + 1
        static.staticID = nextStaticID[interfaceID]
    elseif type(static.staticID) == "number" then
        nextStaticID[interfaceID] = math.max(nextStaticID[interfaceID] or 0, static.staticID)
    end
    component.staticID = static.staticID
    local host = namespaces[interfaceID][static.staticID]
    if not host then
        host = { static = static }
        namespaces[interfaceID][static.staticID] = host
    end
    if parent and parent ~= component then
        component.parent = parent
        component.parentStatic = static
        addChild(parent, component)
        local category = categoryID or component.categoryID
        if category == nil then
            category = parent.categoryID == -1 and 0 or parent.categoryID
        end
        if category == nil then category = 0 end
        local id = dynamicID or component.dynamicID
        if id == nil then
            id = parent.categoryID == -1 and 0 or ((parent.dynamicID or -1) + 1)
            while host[category] and host[category][id] and isLive(host[category][id]) do
                id = id + 1
            end
        end
        component.categoryID, component.dynamicID = category, id
        host[category] = host[category] or {}
        host[category][id] = component
    else
        -- A native rebuild can replace the object without changing its full ID.
        host.static = component
        component.parentStatic = component
        component.categoryID = component.categoryID or -1
        component.dynamicID = component.dynamicID or -1
    end
    if component.IterateDynamicComponents == nil then
        function component:IterateDynamicComponents(callback)
            local children = self.children or self.dynamicComponents or {}
            for _, child in ipairs(children) do
                if isLive(child) and callback(child, not child.hidden) then return end
            end
        end
    end
    if tracked[component] == interfaceID then install(); return component end
    components[interfaceID][#components[interfaceID] + 1] = component
    tracked[component] = interfaceID
    install()
    return component
end

-- Reject every property access after unload, including attempts to read IDs.
function Interfaces.unload(interfaceID)
    for id, handles in pairs(components) do
        if interfaceID == nil or id == interfaceID then
            loaded[id] = nil
            namespaces[id] = nil
            components[id] = nil
            for _, component in ipairs(handles) do
                for key in pairs(component) do component[key] = nil end
                setmetatable(component, {
                    __index = function(_, key) error("read after interface unload: " .. tostring(key)) end,
                    __newindex = function(_, key) error("write after interface unload: " .. tostring(key)) end,
                })
            end
        end
    end
end

return Interfaces
