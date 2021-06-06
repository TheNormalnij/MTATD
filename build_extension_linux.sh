#!/bin/bash

echo "Build Go DebugServer"
cd TestServer
set GOARCH=386
go build -o ../VSCode_Extension/DebugServerLinux *.go
cd ..

echo "Compress binary"
./tools/upx -4 VSCode_Extension/DebugServerLinux

echo "Create Lua bundle"
cd LuaLibrary
mkdir ../VSCode_Extension/debugger_mta_resource
cp -r debugger/* ../VSCode_Extension/debugger_mta_resource
cd ..

echo "Build VSCode extension vsix"
cd VSCode_Extension
vsce package
cd ..
