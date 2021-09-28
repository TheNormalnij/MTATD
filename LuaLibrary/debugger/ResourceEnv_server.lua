
ResourceEnv.stopEventName = "onResourceStop"
ResourceEnv.startEventName = "onResourceStart"

function ResourceEnv:_platformInit()
	self:initDatabaseFunctions()
end

function ResourceEnv:_destroyPlatform()
	self:cleanDatabaseFunctions()
end

function ResourceEnv:initDatabaseFunctions()
	local env = self._env
	self._databases = {}

	local function addCreateDatabaseFunction( owner, functionName, classTable )
		local _fun = owner[functionName]
		owner[functionName] = function( ... )
			local result = _fun( ... )
			if result then
				self:_fixClassObject( result, classTable )
				self._databases[result] = true
				return result
			else
				error("Can not create object", 2)
			end
		end
	end

	addCreateDatabaseFunction( env, "dbConnect", env.Connection )
	addCreateDatabaseFunction( env.Connection, "create", env.Connection )

	env.dbQuery = function( __queryCallback, ... )
		if type( __queryCallback ) == "function" then
			local fun = function( ... )
				local arg = { ... }
				CurrentEnv = env
				self._debugger:debugRun( function() __queryCallback( self:_unpackFixed( arg ) ) end ) 
				CurrentEnv = _G
			end
			dbQuery( fun, ... )
		else
			return dbQuery( __queryCallback, ... )
		end
	end

	env.Connection.query = function( db, __queryCallback, ... )
		if type( __queryCallback ) == "function" then
			local fun = function( ... )
				local arg = { ... }
				CurrentEnv = env
				self._debugger:debugRun( function() __queryCallback( self:_unpackFixed( arg ) ) end ) 
				CurrentEnv = _G
			end
			Connection.query( db, fun, ... )
		else
			return Connection.query( db, __queryCallback, ... )
		end
	end
end

function ResourceEnv:cleanDatabaseFunctions()
	for database in pairs( self._databases ) do
		if isElement( database ) then
			destroyElement( database )
		end
	end
end

function ResourceEnv:initBindKeysFunctions()
	self._keyBinds = {}
	local function getBindData( player, key, state, fun )
		for id, data in pairs( self._keyBinds ) do
			if data[1] == player and data[2] == key and data[3] == state and data[4] == fun then
				return id, data
			end
		end
	end

	self._env.bindKey = function( player, key, state, func )
		if type( func ) ~= "function" then
			error( "Bad argument #3 in bindKey", 2 )
		end
		if getBindData( player, key, state, fun ) then
			error( "Key already bound", 2 )
		end
		local __fun = function( ... )
			local arg = { ... }
			CurrentEnv = self._env
			self._debugger:debugRun( function() func( self:_unpackFixed( arg ) ) end ) 
			CurrentEnv = _G
		end

		table.insert( self._keyBinds, { player, key, state, func, __fun } )

		bindKey( player, key, state, __fun )
	end

	self._env.unbindKey = function( player, key, state, fun )
		for id, data in pairs( self._keyBinds ) do
			if data[1] == player
				and data[2] == key
				and (state == nil or data[3] == state)
				and (fun == nil or data[4] == fun)
			then
				unbindKey( data[1], data[2], data[3], data[5] )
				self._keyBinds[id] = nil
			end
		end
	end

	self._playerQuitHandler = function()
		local player = source
		for id, data in pairs( self._keyBinds ) do
			if data[1] == player then
				self._keyBinds[id] = nil
			end
		end
	end
	addEventHandler( "onPlayerQuit", root, self._playerQuitHandler )
end

function ResourceEnv:cleanBindKeysFunctions()
	for id, data in pairs( self._keyBinds ) do
		unbindKey( data[1], data[2], data[3], data[5] )
	end

	removeEventHandler( "onPlayerQuit", root, self._playerQuitHandler )
end