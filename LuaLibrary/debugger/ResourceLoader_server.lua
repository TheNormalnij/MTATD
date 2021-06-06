
function ResourceLoader:load()

    local function preStartHandler( resource )
        outputDebugString( "Resource will be loaded in debug mode...", 3 )
        cancelEvent()
    end
    addEventHandler( "onResourcePreStart", root, preStartHandler )

    -- Unpack resource
    startResource( self._resource, false, false, true, true, false, true, true, false, true )
    removeEventHandler( "onResourcePreStart", root, preStartHandler )

    self:parseTargetResourceMeta()

    self._scripts = self._serverScripts
    self._exports = self._serverExports
    local resourceName = self._resource:getName()

    local childResource
    for i, resourceName in pairs( self._includeResources ) do
        childResource = Resource.getFromName( resourceName )
        if childResource and childResource:getState() ~= "running" then
            self._debugger:startDebugResource( childResource )
        end
    end

    local clientScripts = {}
    local hashes = {}
    for i, fileName in pairs( self._clientScripts ) do
        local path = (":%s/%s"):format( resourceName, fileName ) 
        local file = File.open( path )
        local content = file:read( file:getSize() )
        file:close()
        table.insert( clientScripts, { fileName, content })
    end

    -- Really Start
    local function resourceStartHandler( resource )
        local resourceRoot = self._resource:getRootElement()
        resourceRoot:setData( "__client_scripts", clientScripts )
        resourceRoot:setData( "__client_exports", self._clientExports )
        resourceRoot:setData( "__debug", true )

        self:loadResourceEnv()
    end
    addEventHandler( "onResourceStart", root, resourceStartHandler, true, "high+999999999" )

    local isStarted = startResource( self._resource, false, false, true, true, false, true, true, false, true )

    removeEventHandler( "onResourceStart", root, resourceStartHandler )

    return isStarted
end

function ResourceLoader:parseTargetResourceMeta()
    local meta = XML.load( (":%s/meta.xml"):format( self._resource:getName() ) )
    if not meta then
        return false
    end

    self._serverScripts = {}
    self._clientScripts = {}
    self._includeResources = {}
    self._clientExports = {}
    self._serverExports = {}

    local nodes = meta:getChildren( )
    local node, nodeName, side, filePath, functionName
    for i = 1, #nodes do
        node = nodes[i]
        nodeName = node:getName()
        if nodeName == "script" then
            side = node:getAttribute( "type" )
            filePath = node:getAttribute( "src" )
            if side == "shared" then
                table.insert( self._serverScripts, filePath )
                table.insert( self._clientScripts, filePath )
            elseif side == "client" then
                table.insert( self._clientScripts, filePath )
            else
                table.insert( self._serverScripts, filePath )
            end
        elseif nodeName == "include" then
            table.insert( self._includeResources, node:getAttribute( "resource" ) )
        elseif nodeName == "export" then
            side = node:getAttribute( "type" )
            functionName = node:getAttribute( "function" )
            if side == "shared" then
                table.insert( self._serverExports, functionName )
                table.insert( self._clientExports, functionName )
            elseif side == "client" then
                table.insert( self._clientExports, functionName )
            else
                table.insert( self._serverExports, functionName )
            end
        end
    end

    meta:unload()

    return true
end
