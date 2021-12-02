-----------------------------------------------------------
-- PROJECT: MTA:TD - Test and Debug Framework
--
-- LICENSE: See LICENSE in top level directory
-- PURPOSE: MTATD micro class library
------------------------------------------------------------

Class = setmetatable({}, {
    __call = function(self) return setmetatable({}, { __index = self }) end
})

function Class:new(...)
    local obj = setmetatable({}, { __index = self })
    if obj.constructor then
        obj:constructor(...)
    end
    return obj
end

function Class:delete(...)
    if self.destructor then
        self:destructor(...)
    end
end