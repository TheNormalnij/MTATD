
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

	local _guiCreateStaticImage = env.guiCreateStaticImage
	env.guiCreateStaticImage = function( x, y, w, h, path, ... )
		return _guiCreateStaticImage( x, y, w, h, type(path) == "string" and  self:_transformFilePath( path ), ... )
	end

	env.GuiStaticImage.create = env.guiCreateStaticImage

	local _playSound = env.playSound
	env.playSound = function( path, ... )
		local transformed = self._transformFilePath( path )
		if fileExists( transformed ) then
			return _playSound( transformed, ... )
		else
			return _playSound( path, ... )
		end
	end
	env.Sound.create = env.playSound

	local _playSound3D = env.playSound3D
	env.playSound3D = function( path, ... )
		local transformed = self._transformFilePath( path )
		if fileExists( transformed ) then
			return _playSound3D( transformed, ... )
		else
			return _playSound3D( path, ... )
		end
	end
	env.Sound3D.create = env.playSound3D

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