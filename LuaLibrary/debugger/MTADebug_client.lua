
function MTADebug:_platformInit()
    self._resourcePathes[resource] = resourceRoot:getData( "__base_path" )

    -- Add messages output
    addEventHandler( "onClientDebugMessage", root, function(message, level, file, line)
        message = self:fixPathInString(message)
        local resourceName, pathInResource = file:match( "^(.-)\\(.+)" )
        if resourceName then
            resource = getResourceFromName( resourceName )
            if resource and self._resourcePathes[resource] and pathInResource then
                file = ("%s/%s"):format( self._resourcePathes[resource], pathInResource )
            end
        end
        self:sendMessage(("[Client] %s"):format(message), MessageLevelToType[level], file, line)
    end )

    addEventHandler( "onClientResourceStart", root, function( resource )
        if source:getData( "__debug" ) then
            self:_startResourceDebug( resource )
        end
    end )
end

function MTADebug:_startResourceDebug( resource )
    local resourceRoot = resource:getRootElement()
    self._resourcePathes[resource] = resourceRoot:getData( "__base_path" )

    local handler = ResourceLoader:new( resource, self )
    handler:load()
end