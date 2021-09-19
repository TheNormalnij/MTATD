
function MTADebug:_platformInit()
    self._resourcePathes[resource] = resourceRoot:getData( "__base_path" )

    -- Add messages output
    addEventHandler( "onClientDebugMessage", root, function(message, level, file, line)
        message = self:fixPathInString(message)
        file = file or "<unknown>"
        line = line or 0
        local resourceName, pathInResource = file:match( "^(.-)\\(.+)" )
        if resourceName then
            local resourcePath = self:_getResourceBasePath( getResourceFromName( resourceName ) )
            if resourcePath then
                file = ("%s/%s"):format( resourcePath, pathInResource )
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

function MTADebug:_getResourceBasePath( resource )
    if not resource then
        return '<unknow>'
    end
    local path = self._resourcePathes[resource]
    if path then
        return path
    else
        path = resource:getRootElement():getData( "__base_path" )
        self._resourcePathes[resource] = path
        return path
    end
end