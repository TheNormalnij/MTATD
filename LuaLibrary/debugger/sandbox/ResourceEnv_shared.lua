local resourceExports = {}
local warningGenerated = false

ResourceEnv = Class()

ResourceEnv.currentHandler = false

function ResourceEnv:constructor(resource, debugger)
	self._debugger = debugger
	self._resource = resource
	local resourceName = resource:getName()
	self._resourceName = resourceName
	local resourceRoot = resource:getRootElement()
	self._resourceRoot = resourceRoot
	self._dynElementRoot = resource:getDynamicElementRoot()
	self._startHandlers = {}

	local env = table.copy(DefaultEnv)
	self._env = env
	env.resource = resource
	env.resourceRoot = resourceRoot
	env.debug.debugger = debugger

	-- Fix metatables

	self._currentEnvClasses = {}

	for _, className in pairs( UsedMetateble ) do
		local meta = getmetatable( _G[className] )
		setmetatable( env[className], table.copy(meta) )
		self._currentEnvClasses[ _G[className] ] = env[className]
	end

	for key, value in pairs( env ) do
		if type( value ) == "function" then
			env[key] = self:_handleFunction( value )
		elseif type( value ) == "table" then
			for k, v in pairs( value ) do
				if type( v ) == "function" then
					value[k] = self:_handleFunction( v )	
				end
			end
		elseif type( value ) == "userdata" then
			self:_fixMeta( value )
		end
	end

	env._G = env
	self.string = env.string
	env.setmetatable = setmetatable
	env.rawset = rawset
	env.coroutine.create = coroutine.create

	-- Exports
	self:initCallFunctions()

	-- pcall
	env.pcall = function( __pcallFunction, ... )
		local arg = { ... }
		local result = { self._debugger:debugRun( function() return __pcallFunction( self:_unpackFixed( arg ) ) end ) }
		return self:_unpackFixed( result )
	end

	-- Loadstring
	env.loadstring = function( content, blockName )
		if type( content ) ~= "string" then
			error( "Bad argument 1 for loadstring", 2 )
		end
		if blockName ~= nil and type( blockName ) ~= "string" then
			error( "Bad argument 2 for loadstring", 2 )
		end
		local resource = self._resource
		blockName = blockName or content:sub(1, 60)
		local resourceName, filePath = blockName:match( ":(.-)/(.+)" )
		if resourceName then
			resource = Resource.getFromName( resourceName ) or resource
		end
		local fun, errorMessage = loadstring( content, self._debugger:genDebugLink( resource, filePath or blockName ) )
		if fun then
			setfenv( fun, env )
		end
		return fun, errorMessage
	end

	env.getThisResource = function()
		self:_fixMeta( self._resource )
		return self._resource
	end

	-- Files
	self:initFileFunctions()

	-- Commands
	self:initCommandHandlersFunctions()

	-- XML
	self:initXMLFunctions()

	-- Events
	self:initEventHandlersFunctions()

	-- Timers
	self:initTimerFunctions()

	-- Bindkey
	self:initBindKeysFunctions()

	self:_platformInit()

    addEventHandler( self.stopEventName, resourceRoot, function()
        self:destructor()
    end )
end

local thisResourceDynRoot = resource:getDynamicElementRoot()
function ResourceEnv:_handleFunction( fun )
	return function( ... )
		warningGenerated = false
		-- We need save argument stack size
		local argsCount = select( "#", ... )
		local arg = { ... }
		for i = 1, #arg do
			if type( arg[i] ) == "function" then
				arg[i] = self:_getEnvRunFunction( arg[i] )
			end
		end

		local output = { fun( unpack( arg, 1, argsCount ) ) }
		if warningGenerated and self._debugger.settings.pedantic then
			error( "Pedantic mode - warning generated", 3 )
		end
		local v
		for i = 1, #output do
			v = output[i]
			if type( v ) == 'userdata' then
				if isElement( v ) and getElementParent( v ) == thisResourceDynRoot then
					setElementParent( v, self._dynElementRoot )
				end
				self:_fixMeta( v )
			elseif type( v ) == "table" then
				self:_fixMetaInTableDeep( v )
			end
		end

		return unpack( output )
	end
end

function ResourceEnv:_fixClassObject( obj )
	local prevmeta = getmetatable( obj )
	if not prevmeta.__debuggable then
		local index = prevmeta.__index
		prevmeta.__index = function( obj, key )
			local currentHandler = ResourceEnv.currentHandler
			if currentHandler then
				local root = prevmeta
				while true do
					if currentHandler._currentEnvClasses[root.__class][key] then
						return currentHandler._currentEnvClasses[root.__class][key]
					elseif root.__get[key] then
						local result = root.__get[key]( obj )
						self:_fixMetaInTableDeep( result )
						return result
					elseif root.__parent then
						root = root.__parent
					else
						return nil
					end
				end
			else
				return index( obj, key )
			end
		end
		prevmeta.__debuggable = true
	end
end

function ResourceEnv:_fixMeta( val )
	local meta = getmetatable( val )
	if meta and meta.__class and self._currentEnvClasses[ meta.__class ] then
		self:_fixClassObject( val )
	end
end

function ResourceEnv:_fixMetaInTable( vals )
	local meta
	for i = 1, #vals do
		meta = getmetatable( vals[i] )
		if meta and meta.__class and self._currentEnvClasses[ meta.__class ] then
			self:_fixClassObject( vals[i] )
		end
	end
end

function ResourceEnv:_fixMetaInTableDeep( t, cheched )
	local cheched = cheched or {}
	cheched[t] = true
	self:_fixMeta( t )
	if type( t ) == "table" and not cheched[t] then
		for key, value in pairs( t ) do
			self:_fixMetaInTableDeep( key, cheched )
			self:_fixMetaInTableDeep( value, cheched )
		end
	end
end

function ResourceEnv:_unpackFixed( vals )
	self:_fixMetaInTable( vals )
	return unpack( vals )
end


function ResourceEnv:tempValues( values )
	self._temp_backup = {}
	local env = self._env
	for _, key in pairs( values ) do
		self:_fixMeta( _G[key] )
		self._temp_backup[key] = env[key]
		env[key] = _G[key]
	end
end

function ResourceEnv:restoreBackup()
	if self._temp_backup then
		for key, value in pairs( self._temp_backup ) do
			self._env[key] = value
		end
	end
end

function ResourceEnv:_getEnvRunFunction( fun )
	return function( ... )
		local arg = { ... }
		local prevHandler = ResourceEnv.currentHandler
		ResourceEnv.currentHandler = self
		self._debugger:debugRun( function() fun( self:_unpackFixed( arg ) ) end )
		ResourceEnv.currentHandler = prevHandler
	end
end

function ResourceEnv:_transformFilePath( path )
	if path:sub(1, 1) ~= ":" then
		path = (":%s/%s"):format( self._resourceName, path )
	end
	return path
end

function ResourceEnv:_overloadFunctionPath( fun, argNum )
	return function( ... )
		local args = { ... }
		if type( args[argNum] ) == "string" then
			args[argNum] = self:_transformFilePath( args[argNum] )
		end
		return fun( unpack( args ) )
	end
end

function ResourceEnv:_overloadFunctionPathChecked( fun, argNum )
	return function( ... )
		local args = { ... }
		if type( args[argNum] ) == "string" then
			local path = self:_transformFilePath( args[argNum] )
			if fileExists( path ) then
				args[argNum] = path
			end
		end
		return fun( unpack( args ) )
	end
end

function ResourceEnv:initCommandHandlersFunctions()
	self._commands = {}

	local addCommandHandler = self._env.addCommandHandler
	self._env.addCommandHandler = function(cmd, __commandFunction, ... )
		self._commands[cmd] = true
		return addCommandHandler( cmd, self:_getEnvRunFunction( __commandFunction ), ... )
	end
end

function ResourceEnv:cleanCommandHandlersFunctions()
	for cmd in pairs( self._commands ) do
		removeCommandHandler( cmd )
	end
end

function ResourceEnv:initTimerFunctions()
	self._timers = {}
	self._env.setTimer = function( __timerFunction, time, count, ... )
		if type( __timerFunction ) == 'function' then
			local arg = { ... }
			local timer

			local indsideFun = self:_getEnvRunFunction( __timerFunction )

			timer = Timer( function( ... )
				self:tempValues{
					"sourceTimer",
				}
				indsideFun( ... )
				self:restoreBackup()

				if not timer:isValid() or select( 2, timer:getDetails() ) == 1 then
					self._timers[timer] = nil
				end
			end, time, count, ... )

			self._timers[timer] = __timerFunction
			return timer
		end
	end;

	self._env.Timer.create = self._env.setTimer

	self._env.Timer.destroy = function( timer )
		self._timers[timer] = nil
		killTimer( timer )
	end;
end

function ResourceEnv:cleanTimerFunctions()
	for timer in pairs( self._timers ) do
		if isTimer( timer ) then
			killTimer( timer )
		end
	end
end

function ResourceEnv:initEventHandlersFunctions()
	local eventHandlers = {}
	self._eventHandlers = eventHandlers
	self._destroyElementHandler = function()
		eventHandlers[source] = nil
	end 

	addEventHandler( self.destroyElementEventName, resourceRoot, self._destroyElementHandler )

	self._env.addEventHandler = function( eventName, element, __eventFunction, ... )
		if type( __eventFunction ) == 'function' then
			local elementHandlers = eventHandlers[element]
			if not elementHandlers then
				elementHandlers = {}
				eventHandlers[element] = elementHandlers
			end
			local events = elementHandlers[eventName]
			if not events then
				events = {}
				elementHandlers[eventName] = events
			end

			local insideFunction = self:_getEnvRunFunction( __eventFunction )
			local fun
			fun = events[ __eventFunction ] or function( ... )
				local backupKeys = {
					"source",
					"this",
					"sourceResource",
					"sourceResourceRoot",
					"eventName",
				}
				if client then
					table.insert( backupKeys, "client" )
				end
				self:tempValues( backupKeys )

				if self._resource:getState() ~= 'running' then
					removeEventHandler( eventName, element, fun )
					return
				end

				insideFunction( ... )

				self:restoreBackup()
			end;

			local resul = addEventHandler( eventName, element, fun, ... )
			if resul then
				events[ __eventFunction ] = fun

				if eventName == self.startEventName then
					table.insert( self._startHandlers, { fun, element } )
				end
			end
			return resul
		else
			outputDebugString( 'Expected function at argument 3 got ' .. type( _f ), 2 )
			return false
		end
	end;

	self._env.removeEventHandler = function( eventName, element, _f )
		local elementHandlers = eventHandlers[element]
		if not elementHandlers then
			elementHandlers = {}
			eventHandlers[element] = elementHandlers
		end
		local events = elementHandlers[eventName]
		if not events then
			events = {}
			elementHandlers[eventName] = events
		end

		if _f ~= nil then
			return removeEventHandler( eventName, element, events[ _f ] )
		else
			outputDebugString( 'Expected function at argument 3 got ' .. type( _f ), 2 )
			return false
		end
	end;
end

function ResourceEnv:cleanEventHandlersFunctions()
	removeEventHandler( self.destroyElementEventName, resourceRoot, self._destroyElementHandler )

	for element, events in pairs( self._eventHandlers ) do
		if isElement( element ) then
			for eventName, functs in pairs( events ) do
				for original, hooked in pairs( functs ) do
					removeEventHandler( eventName, element, hooked )
				end
			end
		end
	end
end

function ResourceEnv:initFileFunctions()
	self._files = {}

	local _fileOpen = self._env.fileOpen
	self._env.fileOpen = function( path, readOnly )
		local file = _fileOpen( self:_transformFilePath( path ), readOnly )
		if file then
			table.insert( self._files, file )
			return file
		else
			return file
		end
	end
	self._env.File.open = self._env.fileOpen

	local _fileCreate = self._env.fileCreate
	self._env.fileCreate = function( path )
		local file = _fileCreate( self:_transformFilePath( path ) )
		if file then
			table.insert( self._files, file )
			return file
		else
			return file
		end
	end
	self._env.File.new = self._env.fileCreate

	local _fileExists = self._env.fileExists
	self._env.fileExists = function( path )
		return _fileExists( self:_transformFilePath( path ) )
	end
	self._env.File.exists = self._env.fileExists

	self._env.File.create = function( path, readOnly )
		path = self:_transformFilePath( path )
		local file
		if _fileExists( path ) then
			file = _fileOpen( path, readOnly )
		else
			file = _fileCreate( path )
		end
		if file then
			table.insert( self._files, file )
		end

		return file
	end

	local _fileCopy = self._env.fileCopy
	self._env.fileCopy = function( source, target, owerwrite )
		source = self:_transformFilePath( source )
		target = self:_transformFilePath( target )
		return _fileCopy( source, target, owerwrite )
	end 
	self._env.File.copy = self._env.fileCopy

	local _fileClose = self._env.fileClose
	self._env.fileClose = function( file )
		for i, f in pairs( self._files ) do
			if f == file then
				table.remove( self._files, i )
			end
		end
		return _fileClose( file )
	end 
	self._env.File.close = self._env.fileClose

	local _fileDelete = self._env.fileDelete
	self._env.fileDelete = function( path )
		return _fileDelete( self:_transformFilePath( path ) )
	end
	self._env.File.delete = self._env.fileDelete
end

function ResourceEnv:cleanFileFunctions()
	for i, file in pairs( self._files ) do
		fileClose( file )
	end
end

function ResourceEnv:initXMLFunctions()
	self._xml = {}

	local xmlLoadFile = self._env.xmlLoadFile
	self._env.getResourceConfig = function( path )
		local xml = xmlLoadFile( self:_transformFilePath( path ), true )
		if xml then
			table.insert( self._xml, xml )
			return xml
		else
			outputDebugString( "Can't open xml " .. tostring(path), 2 )
		end
	end

	local function _xmlLoadFile( path, readOnly )
		local xml = xmlLoadFile( self:_transformFilePath( path ), readOnly )
		if xml then
			table.insert( self._xml, xml )
			return xml
		else
			--outputDebugString( "Can't open xml " .. tostring(path), 2 )
			return false
		end
	end

	self._env.xmlLoadFile = _xmlLoadFile
	self._env.XML.load = _xmlLoadFile

	local xmlCreateFile = self._env.xmlCreateFile
	local function _xmlCreateFile( path, rootNodeName )
		local xml = xmlCreateFile( self:_transformFilePath( path ), rootNodeName )
		if xml then
			table.insert( self._xml, xml )
			return xml
		else
			outputDebugString( "Can't open xml " .. tostring(path), 2 )
		end
	end

	self._env.xmlCreateFile = _xmlCreateFile
	self._env.XML.create = _xmlCreateFile


	local xmlCopyFile = self._env.xmlCopyFile
	local function _xmlCopyFile( node, path )
		local xml = xmlCopyFile( node, self:_transformFilePath( path ) )
		if xml then
			self:_fixClassObject( xml )
			table.insert( self._xml, xml )
			return xml
		else
			outputDebugString( "Can't open xml " .. tostring(path), 2 )
		end
	end

	self._env.xmlCopyFile = _xmlCopyFile
	self._env.XML.copy = _xmlCopyFile

	local function _xmlUnloadFile( xml )
		for i, f in pairs( self._xml ) do
			if f == xml then
				table.remove( self._xml, i )
			end
		end
		return xmlUnloadFile( xml )
	end 

	self._env.xmlUnloadFile = _xmlUnloadFile
	self._env.XML.unload = _xmlUnloadFile
end

function ResourceEnv:cleanXMLFunctions()
	for i, xml in pairs( self._xml ) do
		xmlUnloadFile( xml )
	end
end

function ResourceEnv:initCallFunctions()
	self._env.call = function( targetResource, funcName, ... )
		if resourceExports[targetResource] then
			return resourceExports[targetResource][funcName]( ... )
		else
			local output = { call( targetResource, funcName, ... ) }
			self:_fixMetaInTableDeep( output )
			return unpack( output )
		end
	end

	local type = type
	local setmetatable = setmetatable
	local getResourceRootElement = getResourceRootElement
	local call = self._env.call
	local getResourceFromName = getResourceFromName
	local tostring = tostring
	local outputDebugString = outputDebugString

	local rescallMT = {}
	function rescallMT:__index(k)
	    if type(k) ~= 'string' then k = tostring(k) end
	        self[k] = function(resExportTable, ...)
	        if type(self.res) == 'userdata' and getResourceRootElement(self.res) then
	            return call(self.res, k, ...)
	        else
			    return nil
	        end
	    end
	    return self[k]
	end

	local exportsMT = {}
	function exportsMT:__index(k)
	    if type(k) == 'userdata' and getResourceRootElement(k) then
	        return setmetatable({ res = k }, rescallMT)
	    elseif type(k) ~= 'string' then
	        k = tostring(k)
	    end

	    local res = getResourceFromName(k)
	    if res and getResourceRootElement(res) then
	        return setmetatable({ res = res }, rescallMT)
	    else
	        outputDebugString('exports: Call to non-running server resource (' .. k .. ')', 1)
	        return setmetatable({}, rescallMT)
	    end
	end
	self._env.exports = setmetatable({}, exportsMT)
end

function ResourceEnv:cleanCallFunctions()
	resourceExports[self._resource] = nil
end

function ResourceEnv:destructor()
	self._resourceRoot:destroy()

	self:cleanTimerFunctions()
	self:cleanCommandHandlersFunctions()
	self:cleanEventHandlersFunctions()
	self:cleanBindKeysFunctions()
	self:cleanFileFunctions()
	self:cleanXMLFunctions()
	self:cleanCallFunctions()

	self:_destroyPlatform()
end

function ResourceEnv:loadFile( filePath )
	local fullPath = (":%s/%s"):format( self._resourceName, filePath )
	local file = File.open( fullPath, true )
	if not file then
		outputDebugString( ("Can not load %s. Disable database_credentials_protection in mtaserver.conf" ):format( fullPath ), 3 )
		return
	end
	local content = file:read( file:getSize() )
	file:close()

	local f, errorMsg = loadstring( content, self._debugger:genDebugLink( self._resource, filePath ) )
	if f then
		setfenv( f, self._env )
		ResourceEnv.currentHandler = self
		self._debugger:debugRun( f )
		ResourceEnv.currentHandler = false
	else
		errorMsg = self._debugger:fixPathInString( errorMsg )
		local file, line = errorMsg:match( "^(.+):(%d+):.+" )
		self._debugger:outputDebugString("Syntax error:" .. errorMsg, 1, file, tonumber( line ) )
	end
end

function ResourceEnv:loadFiles( files )
	for i = 1, #files do
		self:loadFile( files[i] )
	end

	local prev_source = source
	local prev_this = this
	local prev_resourceRoot = resourceRoot
	local prev_sourceResource = sourceResource
	local prev_sourceResourceRoot = sourceResourceRoot
	local prev_eventName = eventName
	local prev_resource = resource

	source = self._resourceRoot
	sourceResource = self._resource
	sourceResourceRoot = self._resourceRoot
	eventName = self.startEventName
	resource = self._resource

	ResourceEnv.currentHandler = self
	for _, handlerData in ipairs( self._startHandlers ) do
		this = handlerData[2]
		handlerData[1]( self._resource )
	end
	ResourceEnv.currentHandler = false

	source = prev_source
	this = prev_this
	resourceRoot = prev_resourceRoot
	sourceResource = prev_sourceResource
	sourceResourceRoot = prev_sourceResourceRoot
	eventName = prev_eventName
	resource = prev_resource
end

function ResourceEnv:allowExports( nameList )
	local exported = {}
	for i, funName in pairs( nameList ) do
		exported[funName] = function( ... )
			local env = self._env
			if not env[funName] then
				error( "Attemt to call not exported function " .. funName, 2 )
			end
			local prevResource, preSourceResourceRoot = env.sourceResource, env.sourceResourceRoot
			env.sourceResource = self._resource
			env.sourceResourceRoot = self._resourceRoot
			local result = table.copy( { env[funName]( ... ) } )
			self:_fixMetaInTableDeep( result )
			env.sourceResource = prevResource
			env.sourceResourceRoot = preSourceResourceRoot

			return unpack( result )
		end
	end

	resourceExports[self._resource] = exported
end

function ResourceEnv:getRunningEnv()
	if self.currentHandler then
		return self.currentHandler._env
	else
		return _G
	end
end

addEventHandler( localPlayer and "onClientDebugMessage" or "onDebugMessage", root, function( message, level, file, line )
	if level == 2 or level == 1 then
		warningGenerated = true
	end
end )

local string = string
getmetatable("").__index = function(str, key)
	if ResourceEnv.currentHandler then
		return ResourceEnv.currentHandler.string[key]
	else
		return string[key]
	end
end