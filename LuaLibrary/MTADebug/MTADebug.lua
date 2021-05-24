-----------------------------------------------------------
-- PROJECT: MTA:TD - Test and Debug Framework
--
-- LICENSE: See LICENSE in top level directory
-- PURPOSE: Shared global variables across the module
------------------------------------------------------------

-- Namespace for the MTADebug library
MTATD.MTADebug = MTATD.Class()
local debug = debug

-- Resume mode enumeration
local ResumeMode = {
    Resume = 0,
    Paused = 1,
    StepInto = 2,
    StepOver = 3,
    StepOut = 4
}
local RequestSuffix = triggerClientEvent and "_server" or "_client"

local MesageTypes = {
    console = 0,
    stdout = 1,
    stderr = 2,
    telemetry = 3, 
}

local MessageLevelToType = {
    [0] = MesageTypes.console;
    [1] = MesageTypes.stderr;
    [2] = MesageTypes.stdout;
    [3] = MesageTypes.console;
}

-----------------------------------------------------------
-- Constructs the MTADebug manager
--
-- backend (MTATD.Backend): The MTATD backend instance
-----------------------------------------------------------
function MTATD.MTADebug:constructor(backend)
    self._backend = backend
    self._breakpoints = {}
    self._resumeMode = ResumeMode.Resume
    self._stepOverStackSize = 0
    self._ignoreGlobalList = self:_composeGlobalIgnoreList()

    -- Enable development mode
    setDevelopmentMode(true)

    -- Send info about us to backend
    if triggerClientEvent then -- Only set the info on the server
        self._backend:request("MTADebug/set_info", {
            resource_name = getResourceName(getThisResource()),
            resource_path = self:_getResourceBasePath()
        })
    end


    -- Add messages output
    local tag = triggerClientEvent and "[Server] " or "[Client] "
    addEventHandler( triggerClientEvent and "onDebugMessage" or "onClientDebugMessage", root, function(message, level, file, line)
        self._backend:sendMessage(("%s %s"):format(tag, message), MessageLevelToType[level], file, line)
    end )

    -- Wait a bit (so that the backend receives the breakpoints)
    debugSleep(1000)

    -- Initially fetch the breakpoints from the backend
    -- and wait till they're received
    self:_fetchBreakpoints(true)

    -- Install debug hook
    debug.sethook(function(...) self:_hookFunction(...) end, "crl")

    -- Update things once per 3 seconds asynchronously
    self._updateTimer = setTimer(
        function()
            -- Update breakpoint list
            self:_fetchBreakpoints()

            -- pull commands
            self:_fetchCommands()
        end,
        500,
        0
    )
end

-----------------------------------------------------------
-- Disposes the MTADebug instance (e.g. stops polling)
-----------------------------------------------------------
function MTATD.MTADebug:destructor()
    if self._updateTimer and isTimer(self._updateTimer) then
        killTimer(self._updateTimer)
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
function MTATD.MTADebug:_hookFunction(hookType, nextLineNumber)
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

    -- Is there a breakpoint and pending line step?
    if (not self:hasBreakpoint(sourcePath, nextLineNumber) and self._resumeMode ~= ResumeMode.StepInto)
        and (self._resumeMode ~= ResumeMode.StepOver or self._stepOverStackSize > 0) then

        -- Continue normally
        return
    end

    outputDebugString("Reached breakpoint")

    self:runDebugLoop(4)
end

function MTATD.MTADebug:runDebugLoop(stackLevel)
    self._stoppedStackLevel = stackLevel
    self._resumeMode = ResumeMode.Paused

    local traceback = {}
    local skip = 2
    for line in debug.traceback("trace", stackLevel):gmatch( "[^\r\n]+" ) do
        if skip == 0 then
            table.insert( traceback, line:sub(2) )
        else
            skip = skip - 1
        end
    end
    traceback = table.concat(traceback, "\n")

    local sourcePath, nextLineNumber = traceback:match( "^(.-):(%d*):? in." )

    sourcePath = sourcePath or "?"
    nextLineNumber = tonumber(nextLineNumber) or 0

    -- Tell backend that we reached a breakpoint
    self._backend:request("MTADebug/set_resume_mode"..RequestSuffix, {
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
        local commands = self._backend:request("MTADebug/pull_commands"..RequestSuffix, {}, false)

        if commands then
            self:_handleCommands( commands )
        else
            continue = true
        end

        if self._resumeMode ~= ResumeMode.Paused then
            continue = true
        end
    until continue

    outputDebugString("Resuming execution...")
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
function MTATD.MTADebug:hasBreakpoint(fileName, lineNumber)
    local breakpoints = self._breakpoints[fileName:lower()]
    if breakpoints then
        return breakpoints[lineNumber]
    end
    return false
end

-----------------------------------------------------------
-- Fetches the breakpoints from the backend and updates
-- the internally stored list of breakpoints
--
-- wait (bool): true to wait till the response is available,
--              false otherwise (defaults to 'false')
-----------------------------------------------------------
function MTATD.MTADebug:_fetchBreakpoints(wait)
    local responseAvailable = false

    self._backend:request("MTADebug/get_breakpoints", {},
        function(breakpoints)
            local basePath = self:_getResourceBasePath()

            -- Clear old breakpoints
            self._breakpoints = {}

            -- Add new breakpoints
            for k, breakpoint in ipairs(breakpoints or {}) do
                -- Prepend resource base path
                breakpoint.file = basePath..breakpoint.file

                if not self._breakpoints[breakpoint.file] then
                    self._breakpoints[breakpoint.file] = {}
                end
                self._breakpoints[breakpoint.file][breakpoint.line] = true
            end

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

function MTATD.MTADebug:_fetchCommands(wait)
    local responseAvailable = false

    self._backend:request("MTADebug/pull_commands"..RequestSuffix, {},
        function(info)
            -- Continue in case of a failure (to prevent a freeze)
            if info then
                self:_handleCommands( info )
            end
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

-----------------------------------------------------------
-- Builds the base path for a resource (the path used
-- in error messages)
--
-- Returns the built base path
-----------------------------------------------------------
function MTATD.MTADebug:_getResourceBasePath()
    local thisResource = getThisResource()

    if triggerClientEvent then -- Is server?
        local organizationalPath = getResourceOrganizationalPath(thisResource):lower()
        return (organizationalPath ~= "" and organizationalPath.."/" or "")..getResourceName(thisResource):lower().."/"
    else
        return getResourceName(thisResource):lower().."/"
    end
end

local function handleVariable( name, value )
    local valueType = type(value)
    return {
        name = tostring(name),
        value = tostring(value),
        type = valueType,
        varRef = valueType == "table" and ref(value) or  0,
    }
end

-----------------------------------------------------------
-- Returns the names and values of the local variables
-- at the "current" stack frame
--
-- Returns a table indexed by the variable name
-----------------------------------------------------------
function MTATD.MTADebug:_getLocalVariables(stackLevel)
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
function MTATD.MTADebug:_getUpvalueVariables(stackLevel)
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
function MTATD.MTADebug:_getGlobalVariables()
    local counter = 0
    local variables = { }

    for k, v in pairs(_G) do
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
function MTATD.MTADebug:_runString(codeString)
    -- Hacked in from 'runcode' resource
	local notReturned

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
	
	return true
end

-----------------------------------------------------------
-- Composes the ignore list for global variables
-- (ignores all functions that are available before the
-- actual script start)
--
-- Returns a key-ed table that contains the ignore list
-----------------------------------------------------------
function MTATD.MTADebug:_composeGlobalIgnoreList()
    -- Put all elements below _G into the ignore list
    -- since the Debugger is the first script that is executed, it's absolutely fine
    local ignoreList = {}

    for k, v in pairs(_G) do
        ignoreList[k] = true -- Use 'pseudo-set' for faster access
    end

    return ignoreList
end

function MTATD.MTADebug:_handleCommands( commands )
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
        self._backend:request("MTADebug/push_commands_result"..RequestSuffix, results )
    end
end

MTATD.MTADebug.Commands = {}

function MTATD.MTADebug.Commands:set_resume_mode( resumeMode )
    self._resumeMode = tonumber( resumeMode )
    return tostring( self._resumeMode )
end

function MTATD.MTADebug.Commands:request_variable( reference, id )
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
        end
        return toJSON(variables, true):gsub("%[(.*)%]", "%1")
    end
end

function MTATD.MTADebug.Commands:run_code( strCode )
    local returnString

    if strCode:sub(1,1) == "/" then
        local command, args = strCode:match( "/([^ ]+) ?(.*)" )
        if command then
            local status
            if triggerClientEvent then
                status = executeCommandHandler( command, getRandomPlayer() or root, args )
            else
                status = executeCommandHandler( command, args )
            end
            returnString = status and "Command executed" or "Can't execute command"
        else
            returnString = "Command syntax error"
        end
    else
        returnString, errorString = self:_runString(strCode)
        returnString = returnString or errorString
    end
    return tostring(returnString)
end

