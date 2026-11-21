std = "lua54"
max_line_length = false -- StyLua owns wrapping.
max_cyclomatic_complexity = false -- The Lua quality runner checks complexity.

local host_globals = {
    "audio",
    "config",
    "Event",
    "game",
    "GameKey",
    "id",
    "Keyboard",
    "log",
    "MiniMenu",
    "Mouse",
    "PersistentDB",
    "Plugin",
    "ScreenConvert",
    "ui",
    "var",
    "Vector3",
    "Vector4",
}

read_globals = host_globals

-- The client discovers this callback in the plugin's global environment.
files["main.lua"].globals = { "PluginShutdown" }

-- Standalone tests replace the client API with fixtures.
files["tests"].globals = host_globals
