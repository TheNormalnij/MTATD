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
        if file then
            message = ("%s%s:%s %s"):format(tag, file, line or 0, message)
        else
            message = ("%s %s"):format(tag, message)
        end
        self._backend:request("MTADebug/send_message", {
            message = message,
            type = MessageLevelToType[level],
        })
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

            -- Check for changing resume mode
            self:_checkForResumeModeChange()

            -- Check for pending eval expression
            self:_checkForPendingEval()
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

        local_variables = self:_getLocalVariables(),
        upvalue_variables = self:_getUpvalueVariables(),
        global_variables = self:_getGlobalVariables()
    })

    -- Wait for resume request
    local continue = false
    repeat
        -- Ask backend
        self._backend:request("MTADebug/get_resume_mode"..RequestSuffix, {},
            function(info)
                -- Continue in case of a failure (to prevent a freeze)
                if not info then
                    continue = true
                end

                self._resumeMode = info.resume_mode
                self._stepOverStackSize = 0

                if info.resume_mode ~= ResumeMode.Paused then
                    continue = true

                    -- Update breakpoints
                    self:_fetchBreakpoints(true)
                end
            end
        )

        -- Sleep a bit (MTA still processes http events internally)
        debugSleep(100)
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

-----------------------------------------------------------
-- Checks for resume mode changes and stores the
-- maybe new resume mode
-----------------------------------------------------------
function MTATD.MTADebug:_checkForResumeModeChange()
    self._backend:request("MTADebug/get_resume_mode"..RequestSuffix, {},
        function(info)
            self._resumeMode = info.resume_mode
        end
    )
end

-----------------------------------------------------------
-- Checks for pending 'evaluate' commands
-----------------------------------------------------------
function MTATD.MTADebug:_checkForPendingEval()
    self._backend:request("MTADebug/get_pending_eval", {},
        function(info)
            if info.pending_eval and info.pending_eval ~= "" then
                -- Run the piece of code
                outputDebugString("RUN STRING: "..info.pending_eval)
                local returnString, errorString = self:_runString(info.pending_eval)

                -- Send result back to backend
                self._backend:request("MTADebug/set_eval_result", {
                    eval_result = "Result: "..tostring(returnString or errorString)
                }, function() end)
            end
        end
    )
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

-----------------------------------------------------------
-- Returns the names and values of the local variables
-- at the "current" stack frame
--
-- Returns a table indexed by the variable name
-----------------------------------------------------------
function MTATD.MTADebug:_getLocalVariables()
    local variables = { __isObject = "" } -- __isObject ensures that toJSON creates a JSON object rather than an array

    -- Get the values of up to 50 local variables
    for i = 1, 50 do
        local name, value = debug.getlocal(4, i)
        if name then
            variables[name] = tostring(value)
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
function MTATD.MTADebug:_getUpvalueVariables()
    local variables = { __isObject = "" }
    local func = debug.getinfo(4, "f").func
    
    if func then
        for i = 1, 50 do
            local name, value = debug.getupvalue(func, i)
            if name then
                variables[tostring(name)] = tostring(value)
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
    local variables = { __isObject = "" }

    for k, v in pairs(_G) do
        if type(v) ~= "function" and type(k) == "string" then
            -- Ignore variables in ignore list
            if not self._ignoreGlobalList[k] then
                counter = counter + 1
                
                if counter <= 50 then
                    variables[k] = tostring(v)
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
