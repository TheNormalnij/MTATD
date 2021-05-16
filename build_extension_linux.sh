#!/bin/bash

echo "Build Go DebugServer"
cd TestServer
set GOARCH=386
go build -o ../VSCode_Extension/DebugServerLinux main.go MTADebugAPI.go MTAServer.go MTAServerAPI.go MTAUnitAPI.go
cd ..

ech "Compress binary"
./tools/upx -4 VSCode_Extension/DebugServerLinux

echo "Create Lua bundle"
cd LuaLibrary
python Minify.py 0
mv MTATD.bundle.lua ..\VSCode_Extension\MTATD.bundle.lua
cd ..

echo "Build VSCode extension vsix"
cd VSCode_Extension
vsce package
