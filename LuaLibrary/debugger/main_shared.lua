-----------------------------------------------------------
-- PROJECT: MTA:TD - Test and Debug Framework
--
-- LICENSE: See LICENSE in top level directory
-- PURPOSE: MTATD main
------------------------------------------------------------

local Host = "localhost"
local Port = "51237"

local Debugger

-- Start MTATD
addEventHandler( triggerClientEvent and "onResourceStart" or "onClientResourceStart", resourceRoot, function()
    -- Initial checks
    if isBrowserDomainBlocked and isBrowserDomainBlocked("localhost") then
        outputChatBox("Please add 'localhost' to your custom whitelist!", 255, 0, 0)
        return
    end

    -- Launch the backend
    Debugger = Backend:new(Host, Port)
end )

-- Destroy MTATD gracefully
addEventHandler(triggerClientEvent and "onResourceStop" or "onClientResourceStop", resourceRoot, function()
    Debugger:destructor()
end, true, "low-9999999" )
