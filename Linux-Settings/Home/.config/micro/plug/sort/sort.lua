VERSION = "0.1.0"

local micro = import("micro")
local config = import("micro/config")

function sort(bp)
    bp:TextFilterCmd({"sort"})
end

function init()
    config.MakeCommand("sort", sort, config.NoComplete)
end
