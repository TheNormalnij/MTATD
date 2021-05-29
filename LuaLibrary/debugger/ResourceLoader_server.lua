
local ClientScripts = {}

addEvent("requestScriptDownload", true)

addEventHandler( "requestScriptDownload", root, function( fileName )
    triggerLatentClientEvent( client, "onClientScriptGet", source, fileName, ClientScripts[fileName] )
end )

function ResourceLoader:load()
    local isStarted = startResource( self._resource, false, true, true, true, false, true, true, false, true )
    if isStarted then
        local serverScrips, clientScripts = self:getScripts()
        self._scripts = serverScrips
        local resourceRoot = self._resource:getRootElement()
        local resourceName = self._resource:getName()

        local hashes = {}
        for i, fileName in pairs( clientScripts ) do
            local path = (":%s/%s"):format( resourceName, fileName ) 
            local file = File.open( path )
            local content = file:read( file:getSize() )
            file:close()
            ClientScripts[path] = content
            hashes[i] = hash( "md5", content )
        end

        resourceRoot:setData( "__client_scripts", clientScripts )
        resourceRoot:setData( "__client_scripts_hashes", hashes )
        resourceRoot:setData( "__resource_name", resourceName )
        triggerClientEvent( "requestStartResourceDebug", resourceRoot, resourceName )

        self:loadResourceEnv()
        return true
    else
        return false
    end
end

function ResourceLoader:getScripts()
    local meta = XML.load( (":%s/meta.xml"):format( self._resource:getName() ) )
    if not meta then
        return false
    end

    local serverScrips = {}
    local clientScripts = {}

    local nodes = meta:getChildren( )
    local node, side, filePath
    for i = 1, #nodes do
        node = nodes[i]
        if node:getName() == "script" then
            side = node:getAttribute( "type" )
            filePath = node:getAttribute( "src" )
            if side == "shared" then
                table.insert( serverScrips, filePath )
                table.insert( clientScripts, filePath )
            elseif side == "client" then
                table.insert( clientScripts, filePath )
            else
                table.insert( serverScrips, filePath )
            end

        end
    end

    meta:unload()

    return serverScrips, clientScripts
end
