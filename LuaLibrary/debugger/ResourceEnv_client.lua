
ResourceEnv.stopEventName = "onClientResourceStop"
ResourceEnv.startEventName = "onClientResourceStart"

function ResourceEnv:_platformInit()
	local env = self._env
	self._guiRoot = guiCreateLabel( 0, 0, 1, 1, '', true )
	env.guiRoot = self._guiRoot

	local _getResourceGUIElement = env.getResourceGUIElement
	env.getResourceGUIElement = function( res )
		if res == nil then
			return self._guiRoot
		else
			-- TODO allow get fake roots
			return _getResourceGUIElement( res )
		end
	end

	self:initBindKeysFunctions()

	env.playSound = self:_overloadFunctionPathChecked( env.playSound, 1 )
	env.Sound.create = self:_overloadFunctionPathChecked( env.Sound.create, 1 )

	env.playSound3D = self:_overloadFunctionPathChecked( env.playSound3D, 1 )
	env.Sound3D.create = self:_overloadFunctionPathChecked( env.Sound3D.create, 1 )

	local _loadBrowserURL = env.loadBrowserURL
	env.loadBrowserURL = function( browser, url, ... )
		if type( url ) == "string" then
			url = url:gsub( "http://mta/(local)/", "http://mta/" .. self._resourceName .. "/" )
		end
		return _loadBrowserURL( browser, url, ... )
	end
	env.Browser.loadURL = env.loadBrowserURL

	env.dxCreateFont = self:_overloadFunctionPathChecked( env.dxCreateFont, 1 )
	env.DxFont.create = self:_overloadFunctionPathChecked( env.DxFont.create, 1 )

	env.dxCreateShader = self:_overloadFunctionPathChecked( env.dxCreateShader, 1 )
	env.DxShader.create = self:_overloadFunctionPathChecked( env.DxShader.create, 1 )

	env.dxCreateTexture = self:_overloadFunctionPathChecked( env.dxCreateTexture, 1 )
	env.DxTexture.create = self:_overloadFunctionPathChecked( env.DxTexture.create, 1 )

	env.dxDrawImage = self:_overloadFunctionPath( env.dxDrawImage, 5 )
	env.dxDrawImageSection = self:_overloadFunctionPath( env.dxDrawImageSection, 9 )

	env.engineLoadCOL = self:_overloadFunctionPathChecked( env.engineLoadCOL, 1 )
	env.EngineCOL.create = self:_overloadFunctionPathChecked( env.EngineCOL.create, 1 )

	env.engineLoadDFF = self:_overloadFunctionPathChecked( env.engineLoadDFF, 1 )
	env.EngineDFF.create = self:_overloadFunctionPathChecked( env.EngineDFF.create, 1 )

	env.engineLoadIFP = self:_overloadFunctionPathChecked( env.engineLoadIFP, 1 )
	--env.EngineIFP.create = self:_overloadFunctionPathChecked( env.EngineIFP.create, 1 )

	env.engineLoadTXD = self:_overloadFunctionPathChecked( env.engineLoadTXD, 1 )
	env.EngineTXD.create = self:_overloadFunctionPathChecked( env.EngineTXD.create, 1 )

	env.guiCreateFont = self:_overloadFunctionPathChecked( env.guiCreateFont, 1 )
	env.GuiFont.create = self:_overloadFunctionPathChecked( env.GuiFont.create, 1 )

	env.guiCreateStaticImage = self:_overloadFunctionPathChecked( env.guiCreateStaticImage, 5 )
	env.GuiStaticImage.create = self:_overloadFunctionPathChecked( env.GuiStaticImage.create, 5 )

	env.guiStaticImageLoadImage = self:_overloadFunctionPathChecked( env.guiStaticImageLoadImage, 2 )
	env.GuiStaticImage.loadImage = self:_overloadFunctionPathChecked( env.GuiStaticImage.loadImage, 2 )

	env.downloadFile = self:_overloadFunctionPathChecked( env.downloadFile, 1 )

	if svgCreate then
		local _svgCreate = env.svgCreate
		env.svgCreate = function( w, h, path, callback, ... )
			if type( path ) == "string" then
				path = self:_transformFilePath( path )
			end
			if callback then
				local _callback = callback
				callback = function( ... )
					local arg = { ... }
					CurrentEnv = self._env
					self._debugger:debugRun( function() _callback( self:_unpackFixed( arg ) ) end ) 
					CurrentEnv = _G
				end
			end
			return _svgCreate( w, h, path, callback, ... )
		end
	end

end

function ResourceEnv:_destroyPlatform()
	self:cleanBindKeysFunctions()

	destroyElement( self._guiRoot )
end

function ResourceEnv:initBindKeysFunctions()
	self._keyBinds = {}
	local function getBindData( key, state, fun )
		for id, data in pairs( self._keyBinds ) do
			if data[1] == key and data[2] == state and data[3] == fun then
				return id, data
			end
		end
	end

	self._env.bindKey = function( key, state, func )
		if type( func ) == "function" then
			if getBindData( key, state, fun ) then
				error( "Key already bound", 2 )
			end
			local __fun = function( ... )
				local arg = { ... }
				CurrentEnv = self._env
				self._debugger:debugRun( function() func( self:_unpackFixed( arg ) ) end ) 
				CurrentEnv = _G
			end
			bindKey( key, state, __fun )
		else
			bindKey( key, state, func )
		end

		table.insert( self._keyBinds, { key, state, func, __fun } )

	end

	self._env.unbindKey = function( key, state, fun )
		for id, data in pairs( self._keyBinds ) do
			if data[1] == key
				and (state == nil or data[2] == state)
				and (fun == nil or data[3] == fun)
			then
				unbindKey( data[1], data[2], data[4] )
				self._keyBinds[id] = nil
			end
		end
	end
end

function ResourceEnv:cleanBindKeysFunctions()
	for id, data in pairs( self._keyBinds ) do
		unbindKey( data[1], data[2], data[4] )
	end
end

local thisResourceDynRoot = resource:getDynamicElementRoot()
local thisResourceGuiRoot = guiRoot
function ResourceEnv:_handleFunction( fun )
	return function( ... )
		local output = { fun( ... ) }
		local v
		for i = 1, #output do
			v = output[i]
			if type( v ) == 'userdata' then
				local parent = isElement( v ) and getElementParent( v )
				if parent == thisResourceDynRoot then
					v:setParent( self._dynElementRoot )
				elseif parent == thisResourceGuiRoot then
					v:setParent( self._guiRoot )
				end
				self:_fixMeta( v )
			elseif type( v ) == "table" then
				self:_fixMetaInTableDeep( v )
			end
		end

		return unpack( output )
	end
end