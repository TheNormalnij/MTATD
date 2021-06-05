
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
    self._envController:loadFiles( self._scripts )

    self._envController:allowExports( self._exports )    
end