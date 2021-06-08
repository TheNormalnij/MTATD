-----------------------------------------------------------
-- PROJECT: MTA:TD - Test and Debug Framework
--
-- LICENSE: See LICENSE in top level directory
-- PURPOSE: Shared global variables across the module
------------------------------------------------------------

-- Namespace for the MTADebug library
MTADebug = Class()
local debug = debug

-- Resume mode enumeration
local ResumeMode = {
    Resume = 0,
    Paused = 1,
    StepInto = 2,
    StepOver = 3,
    StepOut = 4
}

MesageTypes = {
    console = 0,
    stdout = 1,
    stderr = 2,
    telemetry = 3, 
}

MessageLevelToType = {
    [0] = MesageTypes.console;
    [1] = MesageTypes.stderr;
    [2] = MesageTypes.stdout;
    [3] = MesageTypes.console;
}

-----------------------------------------------------------
-- Constructs the MTADebug manager
--
-- backend (Backend): The MTATD backend instance
-----------------------------------------------------------
function MTADebug:constructor(backend)
    self._resourcePathes = {}
    self._debugLinks = {}
    self._debugLinksMap = {}
    self._lastDebugLink = 0
    self._backend = backend
    self._breakpoints = {}
    self._resumeMode = ResumeMode.Resume
    self._stepOverStackSize = 0
    self._ignoreGlobalList = self:_composeGlobalIgnoreList()

    self._started_resources = {}

    -- Enable development mode
    setDevelopmentMode(true)

    -- Install debug hook
    debug.sethook(function(...) self:_hookFunction(...) end, "crl")

    -- Specific client or server init
    self:_platformInit()
end

-----------------------------------------------------------
-- Disposes the MTADebug instance (e.g. stops polling)
-----------------------------------------------------------
function MTADebug:destructor()
    if self._updateTimer and isTimer(self._updateTimer) then
        killTimer(self._updateTimer)
    end
end

function MTADebug:onConnected()
    outputDebugString( "Debugger connected", 3 )

    -- Initially fetch the breakpoints from the backend
    self:_fetchBreakpoints()

     -- Update things once per 0.5 seconds asynchronously
    self._updateTimer = setTimer(
        function()
            -- pull commands
            self:_fetchCommands()
        end,
        500,
        0
    )
end

function MTADebug:onDisconnected()
    outputDebugString( "Debugger disconnected", 3 )
    if self._updateTimer and isTimer( self._updateTimer )then
        self._updateTimer:destroy()
        self._updateTimer = nil
    end
end
-----------------------------------------------------------
-- (Private) function that is called for each line in
-- the script being executed (line hook)
--
-- hookType (string): The hook type string
--                    (this should always be 'line')
-- nextLineNumber (number): The next line that is executed
-----------------------------------------------------------
function MTADebug:_hookFunction(hookType, nextLineNumber)
    if hookType == "call" then
        if self._resumeMode == ResumeMode.StepOver then
            self._stepOverStackSize = self._stepOverStackSize + 1
        end
        return
    end
    if hookType == "return" or hookType == "tail return" then
        if self._resumeMode == ResumeMode.StepOver then
            self._stepOverStackSize = self._stepOverStackSize - 1
        end
        return
    end

    -- Get some debug info
    local debugInfo = debug.getinfo(3, "S")
    local sourcePath =  debugInfo.source:gsub("\\", "/"):sub(2) -- Cut off @ (first character)
    local link = tonumber(sourcePath)
    if link then
        sourcePath = self._debugLinks[link]
    end

    -- Is there a breakpoint and pending line step?
    if (not self:hasBreakpoint(sourcePath, nextLineNumber) and self._resumeMode ~= ResumeMode.StepInto)
        and (self._resumeMode ~= ResumeMode.StepOver or self._stepOverStackSize > 0) then

        -- Continue normally
        return
    end

    outputDebugString("Reached breakpoint", 3)

    self:runDebugLoop(4)
end

function MTADebug:runDebugLoop(stackLevel, message)
    self._stoppedStackLevel = stackLevel
    self._resumeMode = ResumeMode.Paused

    local traceback = {}
    local skip = 2
    local path, lineNumber, dest, link
    for line in debug.traceback("trace", stackLevel):gmatch( "[^\r\n]+" ) do
        if skip == 0 then
            path, lineNumber, dest = line:match( "\t(.-):(%d*):? in (.+)" )
            if path then
                link = path:match( 'string "&(%d+)"' )
            else
                path = "?"
            end

            if link then
                path = self._debugLinks[ tonumber( link ) ]
            end
            if dest then
                if dest:find("^function") then
                    dest = dest:sub(10)
                else
                    dest = self:fixPathInString( dest )
                end
            else
                dest = "?"
            end
            if lineNumber then
                line = ("%s:%s: in %s"):format(path, lineNumber, dest)
            else
                line = ("%s: in %s"):format(path, dest)
            end
            table.insert( traceback, line )
            if dest == "main chunk" then
                -- Don't show trace inside debugger resource
                break;
            end
        else
            skip = skip - 1
        end
    end
    traceback = table.concat(traceback, "\n")

    local sourcePath, nextLineNumber = traceback:match( "^(.-):(%d*):? in." )

    sourcePath = sourcePath or "?"
    nextLineNumber = tonumber(nextLineNumber) or 0

    -- Tell backend that we reached a breakpoint
    self._backend:requestPlatform("set_resume_mode", {
        resume_mode = ResumeMode.Paused,
        current_file = sourcePath,
        current_line = nextLineNumber,
        traceback = traceback,

        global_variables = self:_getGlobalVariables()
    })


    -- Wait for resume request
    local continue = false
    repeat
        -- Ask backend
        local commands = self._backend:requestPlatform("pull_commands", {}, false)

        if commands then
            self:_handleCommands( commands )
        else
            continue = true
        end

        if self._resumeMode ~= ResumeMode.Paused then
            continue = true
        end
    until continue

    self._stoppedStackLevel = nil
    outputDebugString("Resuming execution...", 3)
end

function MTADebug:genDebugLink( resource, filePath )
    if self._debugLinksMap[resource] then
        local debugLink = self._debugLinksMap[resource][filePath]
        if debugLink then
            return "&" .. debugLink
        else
            debugLink = self._lastDebugLink + 1
            self._lastDebugLink = debugLink
            self._debugLinksMap[resource][filePath] = debugLink
            self._debugLinks[debugLink] = self._resourcePathes[resource] .. filePath
            return "&" .. debugLink
        end
    else
        debugLink = self._lastDebugLink + 1
        self._lastDebugLink = debugLink
        self._debugLinksMap[resource] = { [filePath] = debugLink }
        self._debugLinks[debugLink] = self._resourcePathes[resource] .. filePath
        return "&" .. debugLink
    end
end

function MTADebug:fixPathInString(str)
    return str:gsub( '%[string "&(%d+)"%]', function(link)
        link = tonumber(link)
        return self._debugLinks[link]
    end )
end

function MTADebug:getFullFilePath( resource, filePath )
    return self._resourcePathes[resource] .. filePath
end

-----------------------------------------------------------
-- Checks whether or not there is a breakpoint at the
-- given line in the given file
--
-- fileName (string): The file name (relative script path)
-- lineNumber (number): The line number
--
-- Returns true if there is a breakpoint, false otherwise
-----------------------------------------------------------
function MTADebug:hasBreakpoint(fileName, lineNumber)
    local breakpoints = self._breakpoints[fileName]
    if breakpoints then
        return breakpoints[lineNumber]
    end
    return false
end

function MTADebug:_setBreakpoint(fileName, lineNumber)
    local breakpoints = self._breakpoints[fileName]
    if breakpoints then
        breakpoints[lineNumber] = true
    else
        self._breakpoints[fileName] = { [lineNumber] = true }
    end
end

function MTADebug:_updateBreakpoints( breakpoints )
    self._breakpoints = {}

    -- Add new breakpoints
    for k, breakpoint in ipairs(breakpoints or {}) do
        -- Prepend resource base path
        breakpoint.file = breakpoint.file

        if not self._breakpoints[breakpoint.file] then
            self._breakpoints[breakpoint.file] = {}
        end
        self._breakpoints[breakpoint.file][breakpoint.line] = true
    end
end

-----------------------------------------------------------
-- Fetches the breakpoints from the backend and updates
-- the internally stored list of breakpoints
--
-- wait (bool): true to wait till the response is available,
--              false otherwise (defaults to 'false')
-----------------------------------------------------------
function MTADebug:_fetchBreakpoints(wait)
    local responseAvailable = false

    self._backend:request("get_breakpoints", {},
        function(breakpoints)
            self:_updateBreakpoints( breakpoints )
            responseAvailable = true
        end
    )

    -- Wait
    if wait then
        repeat
            debugSleep(25)
        until responseAvailable
    end
end

function MTADebug:_fetchCommands()
    self._backend:requestPlatform("pull_commands", {},
        function(info)
            -- Continue in case of a failure (to prevent a freeze)
            if info then
                self:_handleCommands( info )
            end
        end
    )
end

local function handleVariable( name, value )
    local valueType = type(value)
    local valueRef = 0
    if valueType == "userdata" then
        local utype = getUserdataType( value )
        local ptr = tostring(value):sub(11,-1)

        if isElement( value ) then
            if getAllElementData then
                valueRef = ref(value)
            end
            local etype = getElementType( value )
            if etype == "player" then
                value = "elem:"..etype.."["..getPlayerName( value ).."]" ..ptr
            elseif etype == "vehicle" then
                value = "elem:"..etype.."["..getVehicleName( value ).."]"..ptr
            elseif etype == "object" then
                value = "elem:"..etype.."["..getElementModel( value ).."]"..ptr
            elseif etype == "ped" then
                value = "elem:"..etype.."["..getElementModel( value ).."]"..ptr
            elseif etype == "pickup" then
                local pType
                if getPickupType( value ) == 0 then pType = "health"
                elseif getPickupType( value ) == 1 then pType = "armor"
                elseif getPickupType( value ) == 2 then pType = "weapon["..getWeaponNameFromID(getPickupWeapon( value )).."]"
                else pType = "custom["..getElementModel( value ).."]"    end
                value = "elem:"..etype.."["..pType.."]"..ptr
            elseif etype == "marker" then
                value = "elem:"..etype.."["..getMarkerType ( value ).."]"..ptr
            elseif etype == "team" then
                value = "elem:"..etype.."["..getTeamName ( value ).."]"..ptr
            else
                value = "elem:"..etype..ptr
            end
        elseif utype == "xml-node" then
            value = "xml-node["..xmlNodeGetName( value ).."]" .. ptr
        elseif utype == "resource-data" then
            value = "resource["..getResourceName( value ).."]" .. ptr
        elseif utype == "account" then
            value = "account["..getAccountName( value ).."]" .. ptr
        elseif utype == "acl" then
            value = "acl["..aclGetName( value ).."]" .. ptr
        elseif utype == "acl-group" then
            value = "acl-group["..aclGroupGetName( value ).."]" .. ptr
        elseif utype == "vector4" or utype == "vector3" or utype == "vector2" or utype == "matrix" then
            value = tostring( value )
        else
            value = utype..ptr
        end

    elseif valueType == "table" then
        valueRef = ref(value)
        value = tostring(value)
    else
        value = tostring(value)
    end
    return {
        name = tostring(name),
        value = value,
        type = valueType,
        varRef = valueRef,
    }
end

-----------------------------------------------------------
-- Returns the names and values of the local variables
-- at the "current" stack frame
--
-- Returns a table indexed by the variable name
-----------------------------------------------------------
function MTADebug:_getLocalVariables(stackLevel)
    local variables = {} -- __isObject ensures that toJSON creates a JSON object rather than an array

    local name, value
    -- Get the values of up to 50 local variables
    for i = 1, 200 do
        name, value = debug.getlocal(stackLevel, i)
        if name then
            table.insert(variables, handleVariable( name, value ) )
        else
            break;
        end
    end

    return variables
end

-----------------------------------------------------------
-- Returns the names and values of the upvalue variables
-- at the "current" stack frame
--
-- Returns a table indexed by the variable name
-----------------------------------------------------------
function MTADebug:_getUpvalueVariables(stackLevel)
    local variables = { }
    local func = debug.getinfo(stackLevel, "f").func
    
    if func then
        for i = 1, 200 do
            local name, value = debug.getupvalue(func, i)
            if name then
                table.insert(variables, handleVariable( name, value ) )
            else
                break
            end
        end
    end

    return variables
end

-----------------------------------------------------------
-- Returns the names and values of the global variables
--
-- Returns a table indexed by the variable name
-----------------------------------------------------------
function MTADebug:_getGlobalVariables()
    local counter = 0
    local variables = { }

    for k, v in pairs( CurrentEnv ) do
        if type(v) ~= "function" and type(k) == "string" then
            -- Ignore variables in ignore list
            if not self._ignoreGlobalList[k] then
                counter = counter + 1
                
                if counter <= 200 then
                    table.insert(variables, handleVariable( k, v ) )
                else
                    break
                end
            end
        end
    end

    return variables
end

-----------------------------------------------------------
-- Loads and runs a given string
--
-- codeString (string): The string you want to run
--
-- Returns the result as the 1st parameter and maybe an
-- error as the 2nd parameter
-----------------------------------------------------------
function MTADebug:_runString(codeString, env)
    -- Hacked in from 'runcode' resource

	-- First we test with return
	local commandFunction, errorMsg = loadstring("return "..codeString)
	if errorMsg then
		-- It failed.  Lets try without "return"
		commandFunction, errorMsg = loadstring(codeString)
	end
	if errorMsg then
		-- It still failed.  Print the error message and stop the function
		return nil, errorMsg
	end

    setfenv(commandFunction, env or _G)

	-- Finally, lets execute our function
	local results = { pcall(commandFunction) }
	if not results[1] then
		return nil, results[2]
	end
	
	local resultsString = ""
	local first = true
	for i = 2, #results do
		if first then
			first = false
		else
			resultsString = resultsString..", "
		end
		local resultType = type(results[i])
		if isElement(results[i]) then
			resultType = "element:"..getElementType(results[i])
		end
		resultsString = resultsString..tostring(results[i]).." ["..resultType.."]"
	end
	
	if #results > 1 then
		return resultsString
	end
	
	return "nil"
end

-----------------------------------------------------------
-- Composes the ignore list for global variables
-- (ignores all functions that are available before the
-- actual script start)
--
-- Returns a key-ed table that contains the ignore list
-----------------------------------------------------------
function MTADebug:_composeGlobalIgnoreList()
    -- Put all elements below _G into the ignore list
    -- since the Debugger is the first script that is executed, it's absolutely fine
    local ignoreList = {}

    for k, v in pairs(_G) do
        ignoreList[k] = true -- Use 'pseudo-set' for faster access
    end

    return ignoreList
end

function MTADebug:_handleCommands( commands )
    if #commands == 0 then
        return
    end
    local results = {}
    local commandData, result
    for i = 1, #commands do
        commandData = commands[i]
        if self.Commands[ commandData.command ] then
            commandData.args = commandData.args or {}
            result = self.Commands[ commandData.command ]( self, unpack( commandData.args ) ) or false
            if commandData.answer_id and commandData.answer_id ~= 0 and result then
                table.insert(results, {
                    answer_id = commandData.answer_id,
                    result = result,
                })
            end
        else
            outputDebugString( "Can not find handler for debugger command " .. commandData.command, 1 )
        end
    end
    if #results ~= 0 then
        self._backend:requestPlatform("push_commands_result", results )
    end
end

-----------------------------------------------------------
-- Run function in debug mode
-----------------------------------------------------------
function MTADebug:debugRun(fun)
    return xpcall(fun, function(errorMessage)
        errorMessage = self:fixPathInString( errorMessage )
        local file, line = errorMessage:match( "^(.+):(%d+):.+" )
        self:outputDebugString( errorMessage, 1, file, tonumber( line ) )
        self:runDebugLoop(3, errorMessage)
    end)
end

-----------------------------------------------------------
-- Send message to debug console
-----------------------------------------------------------
local allowMessages = true

function MTADebug:sendMessage(message, type, file, line, variableReference)
    if allowMessages then
        self._backend:request("send_message", {
            message = message,
            type = type,
            file = file,
            line = line,
            varRef = variableReference,
        })
    end
end

function MTADebug:outputDebugString( message, level, file, line )
    level = level or 0
    allowMessages = false
    outputDebugString( message, level )
    allowMessages = true
    self:sendMessage( message, MessageLevelToType[level], file, line )
end

MTADebug.Commands = {}

function MTADebug.Commands:set_breakpoints( breakpoins, count )
    breakpoins = fromJSON( "["..breakpoins.."]" )
    self:_updateBreakpoints( breakpoins )
end

function MTADebug.Commands:set_resume_mode( resumeMode )
    self._resumeMode = tonumber( resumeMode )
    return tostring( self._resumeMode )
end

function MTADebug.Commands:request_variable( reference, id )
    if id and id ~= "" then
        local varType, stackLevel = id:match( "^(%w+)_(%d+)" )
        stackLevel = tonumber( stackLevel )
        local variables
        if varType == "local" then
            variables = self:_getLocalVariables( self._stoppedStackLevel + stackLevel + 3 )
        elseif varType == "upvalue" then
            variables = self:_getUpvalueVariables( self._stoppedStackLevel + stackLevel + 3 )
        else
            -- We don't need  get global variables
            variables = {}
        end


        return toJSON(variables, true):gsub("%[(.*)%]", "%1")
    else
        local variables = {}
        local refValue = deref(tonumber(reference))
        if type(refValue) == "table" then
            for key, value in pairs(refValue) do
                table.insert(variables, handleVariable( key, value ))
            end
        elseif isElement( refValue ) and getAllElementData then
            local data = getAllElementData( refValue )
            iprint( data )
            for key, value in pairs( data ) do
                table.insert(variables, handleVariable( key, value ))
            end
        end
        return toJSON(variables, true):gsub("%[(.*)%]", "%1")
    end
end

function MTADebug.Commands:run_code( strCode )
    local returnString
    local env
    if self._stoppedStackLevel then
        local stackLevel = self._stoppedStackLevel + 2
        local debugFun = debug.getinfo(self._stoppedStackLevel + 2, "f").func
        local localVariables, localStack = {}, {}
        local upvalueVariables, upvalueStack = {}, {}
        local varName, varValue, i

        i = 1
        while true do
            varName, varValue = debug.getlocal( stackLevel, i )
            if varName then
                localVariables[varName] = varValue
                localStack[varName] = i
                i = i + 1
            else
                break
            end
        end

        i = 1
        while true do
            varName, varValue = debug.getupvalue( debugFun, i )
            if varName then
                upvalueVariables[varName] = varValue
                upvalueStack[varName] = i
                i = i + 1
            else
                break
            end
        end

        env = setmetatable( {},
            {
                __index = function( _, key )
                    if localStack[key] then
                        return localVariables[key]
                    elseif upvalueStack[key] then
                        return upvalueVariables[key]
                    else
                        return CurrentEnv[key]
                    end
                end,

                __newindex = function( _, key, value )
                    if localStack[key] then
                        localVariables[key] = value
                        debug.setlocal(stackLevel + 4, localStack[key], value)
                    elseif upvalueStack[key] then
                        upvalueVariables[key] = value
                        debug.setupvalue(debugFun, upvalueStack[key], value)
                    else
                        CurrentEnv[key] = value
                    end
                end,
            }
        )
    else
        env = _G
    end

    returnString, errorString = self:_runString(strCode, env)
    returnString = errorString or returnString

    return tostring(returnString)
end

