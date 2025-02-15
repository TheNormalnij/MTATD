-----------------------------------------------------------
-- PROJECT: MTA:TD - Test and Debug Framework
--
-- LICENSE: See LICENSE in top level directory
-- PURPOSE: The backend interface (communicates with the backend)
------------------------------------------------------------
local requestSuffix = triggerClientEvent and "_server" or "_client"

Backend = Class()

-----------------------------------------------------------
-- Launches the test and debug framework
-----------------------------------------------------------
function Backend:constructor(host, port)
    -- Network config
    self._host = host
    self._port = port

    -- Build base URL
    self._baseUrl = ("http://%s:%d/MTADebug/"):format(host, port)

    -- Connect status
    self._connected = false

    -- Connect to backend
    self:connect(host, port)
end

-----------------------------------------------------------
-- Stops the test and debug framework
-----------------------------------------------------------
function Backend:destructor()
    -- Destroy debugger
    self._delegate:delete()
end

-----------------------------------------------------------
-- Sets debugger delegate
-----------------------------------------------------------
function Backend:setDelegate(delegate)
    self._delegate = delegate
end

-----------------------------------------------------------
-- Connects to the backend via HTTP
--
-- host (string): The hostname or IP
-- port (number): The port
-----------------------------------------------------------
function Backend:connect(host, port)
    -- Make initial request to check if the backend is running
    self:request( "welcome", {}, function()
        self._connected = true
        self._delegate:onConnected()
    end )
end

-----------------------------------------------------------
-- Sends a request with data to the backend
--
-- name (string): The request identifier (use <MODULE>/<action>)
-- data (table): The data that is sent to the backend
--      (must be serializable using toJSON)
-- callback (function(responseData)): Called when the
--       unserialized response arrives.
--       If callback == false, returns the response object synchronously
-----------------------------------------------------------
function Backend:request(name, data, callback)
    local responseObject = nil
    if data then
        data = toJSON(data):gsub("%[(.*)%]", "%1") -- Fix object being embedded into a JSON array
    end

    if not (self._connected or name == "welcome") then
        return
    end

    local result = fetchRemote(self._baseUrl..name, name,
        function(response, errno)
            if errno == 7 then
                if self._connected then
                    self._connected = false
                    self._delegate:onDisconnected()
                    self:connect( self._host, self._port )
                end

                if name == "welcome" then
                    self:connect( self._host, self._port )
                end

                responseObject = false -- Make sure we don't run into a freeze'
                return
            end
            if errno ~= 0 then
                error("Could not reach backend (code "..errno..") with "..self._baseUrl..name)
                responseObject = false -- Make sure we don't run into a freeze'
                return
            end

            -- Unserialize response and call callback
            local obj = fromJSON("["..response.."]")
            if callback then
                callback(obj)
            else
                responseObject = obj
            end
        end,
        data
    )

    -- Dirty hack. We need add a new request to avoid 5 seconds cooldown
    fetchRemote("http://localhost:666", name, 1, 5, function() end )

    if callback == false then
        repeat
            debugSleep(25)
        until responseObject ~= nil

        return responseObject
    else
        return result
    end
end

function Backend:requestPlatform( name, data, callback )
    name = name .. requestSuffix
    return self:request(name, data, callback)
end

function Backend:reportTestResults(testResults)
    -- Build JSON object
    --[[local data = {}
    for testSuite, results in pairs(testResults) do
        -- Reformat data
        -- TODO
    end]]

    self:request("MTAUnit/report_test_results", testResults)
end
