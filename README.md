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

## Screenshots
![Debugger Screenshot](https://i.imgur.com/5CJU6D3.png)

## Planned Features
* Step into functions (+ return from function)
* Variable editing
* Better debug messages

## Usage
1) When you start debugging, _Visual Studio Code_ asks you to create a new launch configuration based upon a default configuration.  
Make then sure you insert a valid `serverpath` (the path to the server folder **without** `MTA Server.exe`).   
2) Add the _debug bundle_ to your project by executing the command `MTA:TD: Add bundle to current project` (press `F1`, enter the command and submit). This only works if you opened the root folder of your resource (_meta.xml_ lies there).   
3) Add the bundle file to your `meta.xml`:
   ```xml
   <script src="MTATD.bundle.lua" type="shared"/>
   ```
4) Launch the debug test server by pressing _F1_ in _Visual Studio Code_ and entering `MTA:TD: Start MTA Debug Server` (the auto-completion will help you). You could also create a key mapping for this command.   
5) You're ready to start debugging now!

You can run any function in debug mode via `debugRun` method.
   ```lua
   function testFucntion()
      return 5 + nil
   end

   Debugger:debugRun(testFucntion)
   ```
Debugger will stop execution execution on error and call breakpoint in error line.

## Changelog
See [CHANGELOG.md](https://github.com/Jusonex/MTATD/blob/master/VSCode_Extension/CHANGELOG.md)
