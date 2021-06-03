
ResourceLoader = Class()

function ResourceLoader:constructor(resource, debugger)
    self._resource = resource
    self._debugger = debugger
end

function ResourceLoader:destructor()
    self._envController:delete()
end

function ResourceLoader:loadResourceEnv()
    self._envController = ResourceEnv:new( self._resource, self._debugger )
    local resourceName = self._resource:getName()
    for i = 1, #self._scripts do
        self._envController:loadFile( self._scripts[i] )
    end

    self._envController:allowExports( self._exports )    
end