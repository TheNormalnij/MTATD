/*---------------------------------------------------------
 * Copyright (C) Microsoft Corporation. All rights reserved.
 *--------------------------------------------------------*/

import {
	Logger,
	DebugSession, LoggingDebugSession,
	InitializedEvent, TerminatedEvent, StoppedEvent, BreakpointEvent, OutputEvent, Event,
	Thread, StackFrame, Scope, Source, Handles, Breakpoint
} from 'vscode-debugadapter';
import { spawn, ChildProcess } from 'child_process';
import {DebugProtocol} from 'vscode-debugprotocol';
import {readFileSync} from 'fs';
import {basename, normalize} from 'path';
import { platform } from 'os';
import * as request from 'request';


/**
 * This interface should always match the schema found in the mock-debug extension manifest.
 */
export interface LaunchRequestArguments extends DebugProtocol.LaunchRequestArguments {
	/** An absolute path to the MTA server to debug. */
	serverpath: string;
	/** Automatically stop target after launch. If not specified, target does not stop. */
	stopOnEntry?: boolean;
	/** enable logging the Debug Adapter Protocol */
	trace?: boolean;
}

/**
 * The debugger resume state
 */
enum ResumeMode {
	Resume = 0,
	Paused,
	StepInto,
	StepOver,
	StepOut
}

enum MessageTypes {
    console,
    stdout,
    stderr,
    telemetry, 
}

class DebugContext {
	public typeSuffix: string;
	public threadId: number;
	public file: string;
	public line: number;
	public traceback: string;
	public running: boolean = false;

	public localVariables: Object;
	public upvalueVariables: Object;
	public globalVariables: Object;
}

class MTASADebugSession extends DebugSession {
	private _debugProcess;

	// Dummy thread ID for the server and client
	private static SERVER_THREAD_ID = 1;
	private static CLIENT_THREAD_ID = 2;

	// since we want to send breakpoint events, we will assign an id to every event
	// so that the frontend can match events with breakpoints.
	private _breakpointId = 1000;

	// Debug contexts that hold info about variables, file, line etc.
	private _serverContext: DebugContext = new DebugContext();
	private _clientContext: DebugContext = new DebugContext();

	private _currentThreadId: number;

	// maps from sourceFile to array of Breakpoints
	private _breakPoints = new Map<string, DebugProtocol.Breakpoint[]>();

	private _pollPausedTimer: NodeJS.Timer = null;

	private _variableHandles = new Handles<string>();

	private _backendUrl: string = 'http://localhost:51237';

	private _resourcesPath: string;

	private _lastCommandID = 1;

	/**
	 * Creates a new debug adapter that is used for one debug session.
	 * We configure the default implementation of a debug adapter here.
	 */
	public constructor() {
		super();

		this.setDebuggerLinesStartAt1(true);

		// Set thread IDs for contexts
		this._serverContext.typeSuffix = '_server';
		this._clientContext.typeSuffix = '_client';
		this._serverContext.threadId = MTASADebugSession.SERVER_THREAD_ID;
		this._clientContext.threadId = MTASADebugSession.CLIENT_THREAD_ID;
	}

	/**
	 * The 'initialize' request is the first request called by the frontend
	 * to interrogate the features the debug adapter provides.
	 */
	protected initializeRequest(response: DebugProtocol.InitializeResponse, args: DebugProtocol.InitializeRequestArguments): void {
		// This debug adapter implements the configurationDoneRequest.
		//response.body.supportsConfigurationDoneRequest = true;

		// make VS Code to use 'evaluate' when hovering over source
		//response.body.supportsEvaluateForHovers = true;

		// Enable the restart request
		response.body.supportsRestartRequest = true;

		this.sendResponse(response);
	}

	/**
	 * Called when the debugger is launched (and the debugee started)
	 */
	protected launchRequest(response: DebugProtocol.LaunchResponse, args: LaunchRequestArguments): void {
		// if (args.trace) {
		// 	Logger.setup(Logger.LogLevel.Verbose, false);
		// }

        //Get extension path (the DebugServer lays there)
        const extensionPath = normalize(__dirname + '../../..')

        // Start server
        const env_playform = platform();
        if (env_playform == "linux")
        {
            const path = normalize( extensionPath + '/DebugServerLinux');
            this._debugProcess = spawn(path, ['51237'] );
        }
        else if( env_playform == "win32" )
        {
            const path = normalize(extensionPath + '/DebugServer.exe');
            this._debugProcess = spawn(path, ['51237'] );
        }

        if (!this._debugProcess)
        {
        	return
        }

		// Delay request shortly if the MTA Server is not running yet
		let interval: NodeJS.Timer;
		interval = setInterval(() => {		
			// Get info about debuggee
			request(this._backendUrl + '/MTADebug/get_info', (err, res, body) => {
				if (err || res.statusCode != 200) {
					// Try again soon
					return;
				}

				// Apply path from response
				const info = JSON.parse(body);

				this._resourcesPath = normalize(`${args.serverpath}/mods/deathmatch/resources/`);

				// Start timer that polls for the execution being paused
				if (!this._pollPausedTimer)
					this._pollPausedTimer = setInterval(() => { this.checkForPausedTick(); }, 500);

				// We know got a list of breakpoints, so tell VSCode we're ready
				this.sendEvent(new InitializedEvent());

				// We just start to run until we hit a breakpoint or an exception
				this.continueRequest(<DebugProtocol.ContinueResponse>response, { threadId: this._serverContext.threadId });
				this.continueRequest(<DebugProtocol.ContinueResponse>response, { threadId: this._clientContext.threadId });

				// Clear interval as we successfully received the info
				clearInterval(interval)
			});
		}, 200);
	}

	/**
	 * Called when the editor requests a restart
	 */
	protected restartRequest(response: DebugProtocol.RestartResponse, args: DebugProtocol.RestartArguments): void {
		// Send restart command to server
		// request(this._backendUrl + '/MTAServer/command', {
		// 	json: { command: `restart ${this._resourceName}` }
		// }, () => {
		// 	this.sendResponse(response);
		// });
	}

	protected disconnectRequest(response: DebugProtocol.DisconnectResponse, args: DebugProtocol.DisconnectArguments): void {
		if (this._debugProcess){
			this._debugProcess.kill()
		}
	}

	/**
	 * Called when the editor requests a breakpoint being set
	 */
	protected setBreakPointsRequest(response: DebugProtocol.SetBreakpointsResponse, args: DebugProtocol.SetBreakpointsArguments): void {
		const path = args.source.path;

		// Read file contents into array for direct access
		const lines = readFileSync(path).toString().split('\n');

		// Verify breakpoint locations
		const breakpoints = new Array<Breakpoint>();
		args.breakpoints.forEach((sourceBreakpoint) => {
			let l = this.convertClientLineToDebugger(sourceBreakpoint.line);

			if (l < lines.length) {
				// If a line is empty or starts with '--' we don't allow to set a breakpoint but move the breakpoint down
				let line = lines[l - 1].trim();
				while (l < lines.length && (line.length == 0 || line.match(/^\s*--/))) {
					++l;
					line = lines[l - 1].trim();
				}
			}

			const bp = <DebugProtocol.Breakpoint> new Breakpoint(true, this.convertDebuggerLineToClient(l));
			bp.id = this._breakpointId++;
			breakpoints.push(bp);
		});
		this._breakPoints.set(path, breakpoints);

		// Send all breakpoints to backend
		const requestBreakpoints = new Array();
		this._breakPoints.forEach((breakpoints, path) => {
			for (const breakpoint of breakpoints) {
				requestBreakpoints.push({
					file: this.getRelativeResourcePath(path),
					line: this.convertClientLineToDebugger(breakpoint.line)	
				})
			}
		});

		request(this._backendUrl + "/MTADebug/set_breakpoints", {
			json: requestBreakpoints
		}, () => {}); // Pass empty function to use the asynchronous version

		// Send back the actual breakpoint positions
		response.body = {
			breakpoints: breakpoints
		};
		this.sendResponse(response);
	}

	/**
	 * Called to inform the editor about the thread we're using
	 */
	protected threadsRequest(response: DebugProtocol.ThreadsResponse): void {
		// Return the default thread
		response.body = {
			threads: [
				new Thread(MTASADebugSession.SERVER_THREAD_ID, "Server"),
				new Thread(MTASADebugSession.CLIENT_THREAD_ID, "Client")
			]
		};
		this.sendResponse(response);
	}

	/**
	 * Returns a fake 'stacktrace' where every 'stackframe' is a word from the current line.
	 */
	protected stackTraceRequest(response: DebugProtocol.StackTraceResponse, args: DebugProtocol.StackTraceArguments): void {
		const frames = new Array<StackFrame>();
		const debugContext = this.getDebugContextByThreadId(args.threadId);
		this._currentThreadId = args.threadId;
		
		// Only the current stack frame is supported for now
		var framesCount = 0;
		const reg = /(.+?):(\d*):? in (.+)/;
		const lines = debugContext.traceback.match(/[^\r\n]+/g);
		for (var i = 0; lines[i]; i++)
		{
			const frameInfo = reg.exec(lines[i]);
			const path = frameInfo[1];
			const line = Number(frameInfo[2]);
			const functionName = frameInfo[3];

	        const fullFilePath = normalize(this._resourcesPath + path).replace(/\\/g, '/')
			frames.push(new StackFrame(i, functionName, new Source(basename(path),
					this.convertDebuggerPathToClient(fullFilePath)),
					this.convertDebuggerLineToClient(line), 0));

			framesCount++; 
		}
		// Craft response
		response.body = {
			stackFrames: frames,
			totalFrames: framesCount
		};
		this.sendResponse(response);
	}

	/**
	 * Called to inform the editor about the existing variable scopes
	 */
	protected scopesRequest(response: DebugProtocol.ScopesResponse, args: DebugProtocol.ScopesArguments): void {
		const frameReference = args.frameId;
		const scopes = new Array<Scope>();

		scopes.push(new Scope("Local", this._variableHandles.create("local_" + frameReference), false));
		scopes.push(new Scope("Upvalues", this._variableHandles.create("upvalue_" + frameReference), false));
		scopes.push(new Scope("Global", this._variableHandles.create("global_" + frameReference), false));

		response.body = {
			scopes: scopes
		};
		this.sendResponse(response);
	}

	/**
	 * Called to inform the editor about the values of the variables
	 */
	protected variablesRequest(response: DebugProtocol.VariablesResponse, args: DebugProtocol.VariablesArguments): void {
		const variables = [];
		const id = this._variableHandles.get(args.variablesReference);
		const debugContext = this.getDebugContextByThreadId(this._currentThreadId);
		
		// TODO: Use variablesReference to show the entries in tables
		if (id && id.startsWith('global')) {
			for (var i = 0; debugContext.globalVariables[i]; i++) {
				const obj = debugContext.globalVariables[i];
				variables.push({
					name: obj.name,
					type:  obj.type,
					value: obj.value,
					variablesReference: obj.varRef
				});
			}

			response.body = {
				variables: variables
			};
			this.sendResponse(response);
			return
		} else {
			// Send continue request to backend
			const prev = this
			request(this._backendUrl + '/MTADebug/push_command' + debugContext.typeSuffix, {
				json: { command: "request_variable", args: [ String(args.variablesReference), id ], answer_id: this._lastCommandID++ },
				}, (err, status, body) => {
				if (!err && status.statusCode === 200) {
					const objs = JSON.parse(JSON.stringify(body));
					for (var i = 0; objs[i]; i++)
					{
						const obj = objs[i]
						variables.push({
							name: obj.name,
							type:  obj.type,
							value: obj.value,
							variablesReference: obj.varRef
						});
					}
				}

				response.body = {
					variables: variables
				};
				prev.sendResponse(response);
			});

		}
	}

	/**
	 * Called when the editor requests the executing to be continued
	 */
	protected continueRequest(response: DebugProtocol.ContinueResponse, args: DebugProtocol.ContinueArguments): void {
		const debugContext = this.getDebugContextByThreadId(args.threadId);

		// Send continue request to backend
		request(this._backendUrl + '/MTADebug/set_resume_mode' + debugContext.typeSuffix, {
			json: { resume_mode: ResumeMode.Resume }
		}, () => {
			debugContext.running = true;
			this.sendResponse(response);
		});
	}

	/**
	 * Called when a step to the next line is requested
	 */
	protected nextRequest(response: DebugProtocol.NextResponse, args: DebugProtocol.NextArguments): void {
		const debugContext = this.getDebugContextByThreadId(args.threadId);

		// Send step over request to backend
		request(this._backendUrl + '/MTADebug/set_resume_mode' + debugContext.typeSuffix, {
			json: { resume_mode: ResumeMode.StepOver }
		}, () => {
			debugContext.running = true;
			this.sendResponse(response);
		});
	}

	/**
	 * Called when a step into is requested
	 */
	protected stepInRequest(response: DebugProtocol.StepInResponse, args: DebugProtocol.StepInArguments): void {
		const debugContext = this.getDebugContextByThreadId(args.threadId);

		// Send step in request to backend
		request(this._backendUrl + '/MTADebug/set_resume_mode' + debugContext.typeSuffix, {
			json: { resume_mode: ResumeMode.StepInto }
		}, () => {
			debugContext.running = true;
			this.sendResponse(response);
		});
	}

	/**
	 * Called when a step our is requested
	 */
	protected stepOutRequest(response: DebugProtocol.StepOutResponse, args: DebugProtocol.StepOutArguments): void {
		const debugContext = this.getDebugContextByThreadId(args.threadId);

		// Send step in request to backend
		request(this._backendUrl + '/MTADebug/set_resume_mode' + debugContext.typeSuffix, {
			json: { resume_mode: ResumeMode.StepOut }
		}, () => {
			debugContext.running = true;
			this.sendResponse(response);
		});
	}

	/**
	 * Called when the editor requests an eval call
	 */
	protected evaluateRequest(response: DebugProtocol.EvaluateResponse, args: DebugProtocol.EvaluateArguments): void {
		const parent = this

		var command
		var commad_args

		if (args.expression[0] == "!") {
			const reg = /!([^ ]+) ?(.*)/;
			const cmd = reg.exec(args.expression);
			command = cmd[1]
			commad_args = cmd[2].split( " " );
		}
		else {
			command = "run_code";
			commad_args = [ args.expression ];
		}

		request(this._backendUrl + '/MTADebug/push_command_server', {
			json: { command: command, args: commad_args, answer_id: this._lastCommandID++ }
		}, (err, status, body) => {
			if (!err && status.statusCode === 200) {
				const commandResult = JSON.parse(JSON.stringify(body));
				//const commandResult = body;
				response.body = {
					result: commandResult.res,
					variablesReference: commandResult.var
				};
				parent.sendResponse(response);
			}
		});
	}

	/**
	 * Polls the backend for the current execution state
	 */
	protected checkForPausedTick() {
		request(this._backendUrl + '/MTADebug/get_messages', (err, response, body) => {
			if (!err && response.statusCode === 200) {
				const objs = JSON.parse(body);
				for (var i = 0; objs[i]; i++)
				{
					const obj = objs[i];
					var event = new OutputEvent(obj.message + '\n', MessageTypes[obj.type]);
					if (obj.file) {
						(<DebugProtocol.OutputEvent>event).body.source = new Source(basename(obj.file), normalize(this._resourcesPath + obj.file).replace(/\\/g, '/'));
						(<DebugProtocol.OutputEvent>event).body.line = obj.line;
					}
					(<DebugProtocol.OutputEvent>event).body.variablesReference = obj.varRef;
					this.sendEvent(event);
				}
			}
		});


		request(this._backendUrl + '/MTADebug/get_resume_mode_server', (err, response, body) => {
			if (!err && response.statusCode === 200) {
				const obj = JSON.parse(body);

				// Check if paused
				if (obj.resume_mode == ResumeMode.Paused 
						&& this._serverContext.running) {
					// Store the breakpoint's file and line
					this._serverContext.file = obj.current_file;
					this._serverContext.line = obj.current_line;
					this._serverContext.traceback = obj.traceback;

					this._serverContext.globalVariables = obj.global_variables;

					this._serverContext.running = false;
					this.sendEvent(new StoppedEvent('breakpoint', this._serverContext.threadId));
				}
			}
		});

		request(this._backendUrl + '/MTADebug/get_resume_mode_client', (err, response, body) => {
			if (!err && response.statusCode === 200) {
				const obj = JSON.parse(body);

				// Check if paused
				if (obj.resume_mode == ResumeMode.Paused
					&& this._clientContext.running) {
					// Store the breakpoint's file and line
					this._clientContext.file = obj.current_file;
					this._clientContext.line = obj.current_line;
					this._clientContext.traceback = obj.traceback;

					this._clientContext.globalVariables = obj.global_variables;

					this._clientContext.running = false;
					this.sendEvent(new StoppedEvent('breakpoint', this._clientContext.threadId));
				}
			}
		});
	}


	/**
	 * Returns the relative resource path from an absolute path
	 * @param absolutePath The absolute path
	 * @return The relative path
	 */
	private getRelativeResourcePath(absolutePath: string) {
		const matches = normalize(absolutePath).replace(/\\/g, '/').match(/.*?mods\/deathmatch\/resources\/((?:\[.*\]\/)?.*?\/.*)$/);
		const relativePath: string = matches.length > 0 ? matches[1] : absolutePath;

		return relativePath;
	}

	private log(msg: string, line: number) {
		const e = new OutputEvent(`${msg}: ${line}\n`);
		(<DebugProtocol.OutputEvent>e).body.variablesReference = this._variableHandles.create("args");
		this.sendEvent(e);	// print current line on debug console
	}

	private getDebugContextByThreadId(threadId: number): DebugContext {
		return threadId === MTASADebugSession.CLIENT_THREAD_ID ? this._clientContext : this._serverContext;
	}
}

DebugSession.run(MTASADebugSession);
