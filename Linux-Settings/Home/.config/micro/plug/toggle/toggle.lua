VERSION = "0.1.0"

local micro = import("micro")
local config = import("micro/config")

function toggleOption(bp, args)
    if #args < 1 then
        micro.InfoBar():Error("Not enough arguments")
        return
    end
    local val = config.GetGlobalOption(args[1])
    if type(val) ~= "boolean" then
        micro.InfoBar():Error("Non-boolean option ", args[1])
        return
    end
    config.SetGlobalOptionNative(args[1], not val)
end

function toggleLocalOption(bp, args)
    if #args < 1 then
        micro.InfoBar():Error("Not enough arguments")
        return
    end
    local val = bp.Buf.Settings[args[1]]
    if type(val) ~= "boolean" then
        micro.InfoBar():Error("Non-boolean option ", args[1])
        return
    end
    bp.Buf:SetOptionNative(args[1], not val)
end

function init()
    config.MakeCommand("toggle", toggleOption, config.OptionComplete)
    config.MakeCommand("togglelocal", toggleLocalOption, config.OptionComplete)
end
