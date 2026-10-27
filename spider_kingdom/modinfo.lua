name = "Webber: Spider Kingdom"
description = [[
Fan-made beta expanding Webber's skill tree, spider colonies, couriers and mounts.
Work in progress: some features have not been tested in game.
Feedback and bug reports: https://github.com/DimkaRapirka/Webber-treeskeels-beta/issues
]]
author = "Spider Kingdom"
version = "0.1.1"

api_version = 10

dst_compatible = true
dont_starve_compatible = false
reign_of_giants_compatible = false

-- The skill tree definitions must exist on clients for the UI and validation.
all_clients_require_mod = true
client_only_mod = false

server_filter_tags = { "webber", "skill tree" }

configuration_options =
{
    {
        name = "language",
        label = "Language",
        hover = "Text language for the skill tree and new items.",
        options =
        {
            { description = "Auto", data = "auto", hover = "Russian when Russification Pack for DST is enabled or the game language is Russian; otherwise English." },
            { description = "English", data = "en" },
            { description = "Русский", data = "ru" },
        },
        default = "auto",
    },
    {
        name = "debug",
        label = "Debug log",
        hover = "Print Spider Kingdom debug messages to the log.",
        options =
        {
            { description = "Off", data = false },
            { description = "On", data = true },
        },
        default = false,
    },
}
