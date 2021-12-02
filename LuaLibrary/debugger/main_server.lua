-----------------------------------------------------------
-- PROJECT: MTA:TD - Test and Debug Framework
--
-- LICENSE: See LICENSE in top level directory
-- PURPOSE: MTATD main
------------------------------------------------------------

local debuggerHandler

-- Start MTATD
addEventHandler( "onResourceStart", resourceRoot, function()
    local host = get( "host" ) or "localhost"
    local port = get( "port" ) or "51237"

    resourceRoot:setData( "host", host )
    resourceRoot:setData( "port", port )

    -- Launch the backend
    local backend = Backend:new(host, port)

    -- Launch the debugger
    debuggerHandler = MTADebug:new(backend)
end )

-- Destroy MTATD gracefully
addEventHandler( "onResourceStop", resourceRoot, function()
    if debuggerHandler then
        debuggerHandler:getBackend():destructor()
        debuggerHandler:destructor()
    end
end, true, "low-9999999" )
