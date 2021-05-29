addEvent( "requestStartResourceDebug", true )

function MTADebug:_platformInit()
    -- Add messages output
    addEventHandler( "onClientDebugMessage", root, function(message, level, file, line)
        message = self:fixPathInString(message)
        self:sendMessage(("[Client] %s"):format(message), MessageLevelToType[level], file, line)
    end )

    addEventHandler( "requestStartResourceDebug", root, function( resourceName )
        Timer( function()
        self:_startResourceDebug( Resource.getFromName( resourceName ) )
    end, 5000, 1 )
    end )

    local resName
    for _, resourceRoot in pairs( Element.getAllByType( "resource-root" ) ) do
        resName = resourceRoot:getData()
        if resName then
            self:_startResourceDebug( Resource.getFromName( resName ) )
        end
    end

end

function MTADebug:_startResourceDebug( resource )
    local resourceRoot = resource:getRootElement()
    local scripts = resourceRoot:getData( "__client_scripts" )
    self._resourcePathes[resource] = resourceRoot:getData( "__base_path" )
    if scripts then
        if not self._started_resources[resource] then
             local handler = ResourceLoader:new( resource, self )
             local hashes = resourceRoot:getData( "__client_scripts_hashes" )
             if handler:downloadAndStartResource( scripts, hashes ) then
                self._started_resources[resource] = handler
            end
        end
    end
end