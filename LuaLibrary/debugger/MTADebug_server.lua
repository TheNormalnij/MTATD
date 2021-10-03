
function MTADebug:_platformInit()
    self._backend:request("set_info", {
        version = getThisResource():getInfo( "version" )
    })

	for _, resource in pairs( getResources() ) do
		local resourceRoot = resource:getRootElement()
		if resourceRoot then
			resourceRoot:setData( "__base_path", self:_getResourceBasePath( resource ) )
		end
	end

	resourceRoot:setData( "__base_path", self._resourcePathes[resource] )

    addEventHandler( "onDebugMessage", root, function(message, level, file, line)
    	message = self:fixPathInString(message)
        self:sendMessage(("[Server] %s"):format(message), MessageLevelToType[level], file, line)
    end )

    addEventHandler( "onResourceStart", root, function(resource)
    	self._resourcePathes[resource] = nil
    	source:setData( "__base_path", self:_getResourceBasePath( resource ) )
    	self:sendMessage( "Resource started " .. resource:getName() )
    end )

    addEventHandler( "onResourceStop", root, function(resource)
    	self:sendMessage( "Resource stopped " .. resource:getName() )

    	if self._started_resources[resource] then
    		self._started_resources[resource]:delete()
    		self._started_resources[resource] = nil
    	end
    end )

    if get( "loadAllResourcesInDebug" ) == "true" then
        local function preStartHandler( resource )
        	if not self._started_resources[resource] then
	            outputDebugString( "Resource will be loaded in debug mode...", 3 )
	            cancelEvent()
	            setTimer( function()
	            	self:startDebugResource( resource, false )
	            end, 50, 1 )
	        end
        end
        addEventHandler( "onResourcePreStart", root, preStartHandler )
    end
end

-----------------------------------------------------------
-- Builds the base path for a resource (the path used
-- in error messages)
--
-- Returns the built base path
-----------------------------------------------------------
function MTADebug:_getResourceOrganizationalPath( resource )
    local organizationalPath = getResourceOrganizationalPath(resource)
    return (organizationalPath ~= "" and organizationalPath.."/" or "")..getResourceName(resource).."/"
end

function MTADebug:getFullPath( path )
    if path then
        local link = path:match( 'string "&(%d+)"' )
        if link then
            path = self._debugLinks[ tonumber( link ) ]
        end
        return path
    else
        return "?"
    end
end

function MTADebug:_getResourceBasePath( resource )
    local path = self._resourcePathes[resource]
    if path then
        return path
    else
        path = self:_getResourceOrganizationalPath( resource )
        self._resourcePathes[resource] = path
        return path
    end
end

function MTADebug:startDebugResource( resource, needUnpack )
	if not self._started_resources[resource] then
		 local handler = ResourceLoader:new( resource, self )
		 self._started_resources[resource] = handler
		 if handler:load( needUnpack ) then
		 	return true
		end
		self._started_resources[resource] = nil
		return false
	end
	return false
end

function MTADebug.Commands:start_debug( resourceName )
	local resource = Resource.getFromName( resourceName )
	if resource then
		local success = self:startDebugResource( resource, true )
		return success and "Resource started in debug mode" or "Can't start resource in debug mode"
	end
	return "Can not find resource " .. tostring( resourceName )
end

function MTADebug.Commands:start( resourceName )
	local resource = Resource.getFromName( resourceName )
	if resource then
		local success = Resource.start( resource )
		return success and "Resource started" or "Can't start resource"
	end
	return "Can not find resource " .. tostring( resourceName )
end

function MTADebug.Commands:restart( resourceName )
	local resource = Resource.getFromName( resourceName )
	if resource then
		local success = Resource.restart( resource )
		return success and "Resource restarted" or "Can't restart resource"
	end
	return "Can not find resource " .. tostring( resourceName )
end

function MTADebug.Commands:refresh( resourceName )
	local resource = Resource.getFromName( resourceName )
	local success = refreshResources( false, resource or nil )
	return success and "Successfully refreshed" or "Can't refresh resources"
end

function MTADebug.Commands:refreshall( )
	local success = refreshResources( true )
	return success and "Resources refreshed" or "Can't refresh resources"
end

function MTADebug.Commands:stop( resourceName )
	local resource = Resource.getFromName( resourceName )
	if resource then
		local success = Resource.stop( resource )
		return success and "Resource stopped" or "Can't stop resource"
	end
	return "Can not find resource " .. tostring( resourceName )
end

function MTADebug.Commands:execute_command( strCommand )
    local command, args = strCommand:match( "([^ ]+) ?(.*)" )
    if command then
        local status
        if triggerClientEvent then
            status = executeCommandHandler( command, getRandomPlayer() or root, args )
        else
            status = executeCommandHandler( command, args )
        end
        return status and "Command executed" or "Can't execute command"
    else
        return "Command syntax error"
    end
end
