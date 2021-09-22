function table.copy( t )
	if type(t) == "table" then
		local o = {}
		for k, v in pairs(t) do
			o[k] = table.copy(v)
		end
		return o
	else
		return t
	end
end