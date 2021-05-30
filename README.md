# MTA:TD: MTA:SA Lua Debugger and Test Framework [![Build Status](https://travis-ci.org/Jusonex/MTATD.svg?branch=master)](https://travis-ci.org/Jusonex/MTATD)
This extension implements a debug adapter for MTA:SA's (Multi Theft Auto: San Andreas) Lua. Note that it doesn't work with plain Lua though.

## Features
* Breakpoints
* Step into, Step over
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
* Step into functions (+ return from function)
* Variable editing
* Implement sandbox
* Fix bugs

## Usage
1) When you start debugging, _Visual Studio Code_ asks you to create a new launch configuration based upon a default configuration.  
Make then sure you insert a valid `serverpath` (the path to the server folder **without** `MTA Server.exe`).   
2) Add the _debug resource_ to your project by executing the command `MTA:TD: Add debug resource to current project` (press `F1`, enter the command and submit). This only works if you opened the root folder of your server resources folder
3) Launch the debug test server by pressing _F1_ in _Visual Studio Code_ and entering `MTA:TD: Start MTA Debug Server` (the auto-completion will help you). You could also create a key mapping for this command.
4) Start target resource via `!start_debug resourceName`
5) You're ready to start debugging now!

## Commands

`!start resourceName` - Start resource
`!stop resourceName` -  Stop resource
`!restart resourceName` -  Restart resource
`!start_debug resourceName` - Start resource in debug mode