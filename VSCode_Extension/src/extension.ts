'use strict';

// The module 'vscode' contains the VS Code extensibility API
// Import the module and reference it with the alias vscode in your code below
import * as vscode from 'vscode';

import { exec, ChildProcess } from 'child_process';
import { normalize, join as path_join, basename } from 'path';
import { platform } from 'os';
import * as ps from 'ps-node';
import * as fs from 'fs';

// this method is called when your extension is activated
// your extension is activated the very first time the command is executed
export function activate(context: vscode.ExtensionContext) {

    // The command has been defined in the package.json file
    // Now provide the implementation of the command with  registerCommand
    // The commandId parameter must match the command field in package.json
    context.subscriptions.push(vscode.commands.registerCommand('extension.startMTA', () => {
        // The code you place here will be executed every time your command is executed
        const config = vscode.workspace.getConfiguration('launch');
        let info = config.get<Array<any>>('configurations');
        if (!info) {
            vscode.window.showErrorMessage('Could not find a launch configuration. Please make sure you created one.');
            return;
        }
        
        // Filter 'mtasa' configs
        info = info.filter(v => v.type === "mtasa");

        // Show error if there's no mtasa configuration
        if (!info[0]) {
            vscode.window.showErrorMessage('Could not find a launch configuration of type \'mtasa\'. Make sure you created one.');
            return;
        }

        // Show error if no serverpath is provided
        const serverpath = info[0].serverpath;
        if (!serverpath) {
            vscode.window.showErrorMessage('The path to the MTA:SA server directory is missing. Make sure you added one to your launch configuration.');
            return;
        }

        // Show error if the serverpath is invalid
        if (!fs.existsSync(serverpath) || !fs.statSync(serverpath).isDirectory()) {
            vscode.window.showErrorMessage('The value of the \'serverpath\' variable is invalid. It either doesn\'t exist or it is not a directory');
            return;
        } 

        // Get extension path (the DebugServer lays there)
        const extensionPath = normalize(vscode.extensions.getExtension('jusonex.mtatd').extensionPath);

        const env_playform = platform();
        // Start server
        if (env_playform == "linux")
        {
            const terminal = vscode.workspace.getConfiguration().get("terminal.external.linuxExec");
            const path = normalize(serverpath + '/mta-server64');
            exec(`${terminal} -e "${path}"`);
        }
        else if( env_playform == "win32" )
        {
            const path = normalize(serverpath + '/MTA Server.exe');
            exec(`start "MTA:SA Server [SCRIPT-DEBUG]" "${path}"`);
        }
        else
        {
            vscode.window.showErrorMessage('Unsupported platform');
            return;
        }
    }));

    context.subscriptions.push(vscode.commands.registerCommand('extension.addMTATDResource', () => {
        // Get extension path (the MTATD bundle lays there)
        const extensionPath = vscode.extensions.getExtension('jusonex.mtatd').extensionPath;
        const workspacePath = vscode.workspace.rootPath;

        if (!extensionPath || !workspacePath || extensionPath == '' || workspacePath == '') {
            vscode.window.showErrorMessage('Please open a folder/workspace first!');
            return;
        }

        copyFolderRecursiveSync( path_join( extensionPath, "/debugger_mta_resource/" ) , path_join( workspacePath, "/[debugger]/debugger/" ) );
    }));
}

function copyFileSync( source, target ) {
    var targetFile = target;

    // If target is a directory, a new file with the same name will be created
    if ( fs.existsSync( target ) ) {
        if ( fs.lstatSync( target ).isDirectory() ) {
            targetFile = path_join( target, basename( source ) );
        }
    }

    fs.writeFileSync(targetFile, fs.readFileSync(source));
}

function copyFolderRecursiveSync( source, target ) {
    var files = [];

    // Check if folder needs to be created or integrated
    var targetFolder = target;
    if ( !fs.existsSync( targetFolder ) ) {
        fs.mkdirSync( targetFolder, { recursive: true } );
    }

    // Copy
    if ( fs.lstatSync( source ).isDirectory() ) {
        files = fs.readdirSync( source );
        files.forEach( function ( file ) {
            var curSource = path_join( source, file );
            if ( fs.lstatSync( curSource ).isDirectory() ) {
                copyFolderRecursiveSync( curSource,  path_join( targetFolder, basename( source ) ) );
            } else {
                copyFileSync( curSource, targetFolder );
            }
        } );
    }
}

// this method is called when your extension is deactivated
export function deactivate() {
}