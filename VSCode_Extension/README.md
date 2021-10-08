# MTA:RD: MTA:SA Resources debugger
This extension implements a debug adapter for MTA:SA's (Multi Theft Auto: San Andreas) Lua. Note that it doesn't work with plain Lua though.

## Features
* Breakpoints
* Step into, Step over, Step out
* Variable lists (locals, upvalues, globals)
* Resource restarts
* Integrated *runcode* via VSCode's "Debug Console" feature
* Stack traces
* Debug messages in "Debug Console"
* Commands
* Automatic breakpoint in error line

## Screenshots
![Debugger Screenshot](https://i.imgur.com/5CJU6D3.png)

## Planned Features
* Variable editing
* Fix bugs
* Remote server debug

## Usage
1. Use `resources` folder as root folder for VS Code workspace.
1. When you start debugging, _Visual Studio Code_ asks you to create a new launch configuration based upon a default configuration.  
Make then sure you insert a valid `serverpath` (the path to the server folder **with** `MTA Server.exe`).
1. Add the _debug resource_ to your project by executing the command `MTA:RD: Add debug resource to current project` (press `F1`, enter the command and submit). This only works if you opened the root folder of your server resources folder
1. Create `timeout.longtime` file in MTA server folder.
1. Launch the debug test server by pressing _F1_ in _Visual Studio Code_ and entering `MTA:RD: Start MTA Debug Server` (the auto-completion will help you). You could also create a key mapping for this command.
1. Start target resource via `!start_debug resourceName`
1. You're ready to start debugging now!

## Commands
* `!start resourceName` - Start resource
* `!stop resourceName` -  Stop resource
* `!restart resourceName` -  Restart resource
* `!refresh resourceName` -  Refresh resource
* `!refreshall` -  Refresh all resources
* `!start_debug resourceName` - Start resource in debug mode

## How to use loadstring
`loadstring( sourceCode, ":resourceName/path/to/source.lua" )`

## What does not work
* Disabled OOP. All resources will loaded in OOP mode
* Metatable manipulation with userdata or strings. But you still can extend default classes

## How to report a bug
Please, create issues in [my github respoitory](https://github.com/TheNormalnij/MTATD/issues) 