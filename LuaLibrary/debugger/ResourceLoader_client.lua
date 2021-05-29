
addEvent( "onClientScriptGet", true )

function ResourceLoader:load()
    self:loadResourceEnv()
end

function ResourceLoader:downloadAndStartResource( scripts, hashes )
	self._scripts = scripts

	local resourceRoot = self._resource:getRootElement()

	local needDownload = {}

	local resourceName = self._resource:getName()
	for i, file in pairs( scripts ) do
		local path = (":%s/%s"):format( resourceName, file )
		local file = File.exists( path ) and File.open( path )
		if file then
			local content = file:read( file:getSize() )
			file:close()
			if hashes[i] ~= hash( "md5", content ) then
				needDownload[path] = true
				File.delete( path )
			end
		else
			needDownload[path] = true
		end
	end

	local function loadNext()
		local path = next( needDownload )
		if path then
			triggerLatentServerEvent( "requestScriptDownload", resourceRoot, path )
		else
			self:loadResourceEnv()
		end
	end

	local function processDownload( path, content )
		needDownload[path] = nil
		local file = File.create( path )
		file:write( content )
		file:close()

		loadNext()
	end

	addEventHandler( "onClientScriptGet", resourceRoot, processDownload )

	loadNext()

	return true
end