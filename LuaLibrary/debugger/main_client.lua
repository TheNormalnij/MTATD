-----------------------------------------------------------
-- PROJECT: MTA:TD - Test and Debug Framework
--
-- LICENSE: See LICENSE in top level directory
-- PURPOSE: MTATD main
------------------------------------------------------------

local debuggerHandler

-- Start MTATD
addEventHandler( "onClientResourceStart", resourceRoot, function()
    local host = resourceRoot:getData( "host" )
    local port = resourceRoot:getData( "port" )

    -- Initial checks
    if isBrowserDomainBlocked and isBrowserDomainBlocked(host) then
        outputChatBox(("Please add '%s' to your custom whitelist!"):format( host ), 255, 0, 0)
        return
    end

    -- Launch the backend
    local backend = Backend:new(host, port)

    -- Launch the debugger
    debuggerHandler = MTADebug:new(backend)
end )

-- Destroy MTATD gracefully
addEventHandler( "onClientResourceStop", resourceRoot, function()
    if debuggerHandler then
        debuggerHandler:getBackend():destructor()
        debuggerHandler:destructor()
    end
end, true, "low-9999999" )
