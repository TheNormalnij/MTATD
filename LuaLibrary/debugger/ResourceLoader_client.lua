
addEvent( "onClientScriptGet", true )

function ResourceLoader:load()
    self._scripts = {}

    local resourceRoot = self._resource:getRootElement()
    self._exports = resourceRoot:getData( "__client_exports" )

    local scripts = resourceRoot:getData( "__client_scripts" )
    local resourceName = self._resource:getName()
    if scripts then
    	for i, data in pairs( scripts ) do
    		table.insert( self._scripts, data[1] )
			local file = File.create( (":%s/%s"):format( resourceName, data[1] ) )
			file:write( data[2] )
			file:close()
    	end
    end

    self:loadResourceEnv()
end
