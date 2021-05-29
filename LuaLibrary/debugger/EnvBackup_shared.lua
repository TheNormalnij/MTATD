
DefaultEnv = {}
UsedMetateble = {}
for key, value in pairs( _G ) do
	DefaultEnv[key] = value
	if getmetatable(value) and type(value) == "table" then
		table.insert( UsedMetateble, key )
	end
end

DefaultEnv.DefaultEnv = nil
DefaultEnv.UsedMetateble = nil
DefaultEnv._G = nil
DefaultEnv.resource = nil
DefaultEnv.resourceRoot = nil