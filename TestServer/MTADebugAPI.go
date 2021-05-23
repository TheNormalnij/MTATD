package main

import (
	"net/http"
	"os"
	"strconv"
	"path/filepath"

	"encoding/json"

	"github.com/gorilla/mux"
)

type MTADebugAPI struct {
	Breakpoints       []debugBreakpoint
	CurrentBreakpoint debugBreakpoint

	ClientContext debugContext
	ServerContext debugContext

	Messages []debugMessage
	CommandsServer []debugCommand
	CommandsClient []debugCommand

	Info      debugeeInfo
	MTAServer *MTAServer
}

type debugCommand struct {
	Command string    `json:"command"`
	Args    []string  `json:"args"`
}

type debugBreakpoint struct {
	File string `json:"file"`
	Line int    `json:"line"`
}

type debugMessage struct {
	Message string `json:"message"`
	Type    int    `json:"type"`
	File    string `json:"file"`
	Line    int    `json:"line"`
	VarRef  int    `json:"varRef"`
}

type debugContext struct {
	ResumeMode       int               `json:"resume_mode"`
	File             string            `json:"current_file"`
	Line             int               `json:"current_line"`
	LocalVariables   map[string]string `json:"local_variables"`
	UpvalueVariables map[string]string `json:"upvalue_variables"`
	GlobalVariables  map[string]string `json:"global_variables"`
	Traceback  	     string            `json:"traceback"`
}

type debugeeInfo struct {
	ResourceName string `json:"resource_name"`
	ResourcePath string `json:"resource_path"`
}

func (bp *debugBreakpoint) equals(other *debugBreakpoint) bool {
	return bp.File == other.File && bp.Line == other.Line
}

func NewMTADebugAPI(router *mux.Router, mtaServer *MTAServer) *MTADebugAPI {
	// Create instance
	api := new(MTADebugAPI)
	api.MTAServer = mtaServer

	api.Breakpoints = []debugBreakpoint{}
	api.ServerContext.ResumeMode = 0 // ResumeMode.Resume
	api.ClientContext.ResumeMode = 0 // ResumeMode.Resume

	api.Messages = []debugMessage{}
	api.CommandsServer = []debugCommand{}
	api.CommandsClient = []debugCommand{}

	// Register routes
	router.HandleFunc("/get_info", api.handlerGetInfo)
	router.HandleFunc("/set_info", api.handlerSetInfo)

	router.HandleFunc("/push_command_server", api.handlerPushCommandServer)
	router.HandleFunc("/pull_commands_server", api.handlerPullCommandsServer)
	router.HandleFunc("/push_command_client", api.handlerPushCommandClient)
	router.HandleFunc("/pull_commands_client", api.handlerPullCommandsClient)

	router.HandleFunc("/send_message", api.handlerSendMessage)
	router.HandleFunc("/get_messages", api.handlerGetMessages)

	router.HandleFunc("/get_breakpoints", api.handlerGetBreakpoints)
	router.HandleFunc("/set_breakpoint", api.handlerSetBreakpoint)
	router.HandleFunc("/remove_breakpoint", api.handlerRemoveBreakpoint)
	router.HandleFunc("/clear_breakpoints", api.handlerClearBreakpoints)

	router.HandleFunc("/get_resume_mode_server", api.handlerGetResumeModeServer)
	router.HandleFunc("/get_resume_mode_client", api.handlerGetResumeModeClient)
	router.HandleFunc("/set_resume_mode_server", api.handlerSetResumeModeServer)
	router.HandleFunc("/set_resume_mode_client", api.handlerSetResumeModeClient)

	return api
}

func (api *MTADebugAPI) handlerPushCommandServer(res http.ResponseWriter, req *http.Request) {
	command := debugCommand{}
	err := json.NewDecoder(req.Body).Decode(&command)

	if err != nil {
		panic(err)
	} else {
		api.CommandsServer = append(api.CommandsServer, command)
	}

	json.NewEncoder(res).Encode(&command)
}

func (api *MTADebugAPI) handlerPullCommandsServer(res http.ResponseWriter, req *http.Request) {
	json.NewEncoder(res).Encode(&api.CommandsServer)
	api.CommandsServer = []debugCommand{}
}

func (api *MTADebugAPI) handlerPushCommandClient(res http.ResponseWriter, req *http.Request) {
	command := debugCommand{}
	err := json.NewDecoder(req.Body).Decode(&command)

	if err != nil {
		panic(err)
	} else {
		api.CommandsClient = append(api.CommandsClient, command)
	}

	json.NewEncoder(res).Encode(&command)
}

func (api *MTADebugAPI) handlerPullCommandsClient(res http.ResponseWriter, req *http.Request) {
	json.NewEncoder(res).Encode(&api.CommandsClient)
	api.CommandsClient = []debugCommand{}
}

func (api *MTADebugAPI) handlerSendMessage(res http.ResponseWriter, req *http.Request) {
	message := debugMessage{}
	err := json.NewDecoder(req.Body).Decode(&message)

	if err != nil {
		panic(err)
	} else {
		api.Messages = append(api.Messages, message)
	}

	json.NewEncoder(res).Encode(&message)
}

func (api *MTADebugAPI) handlerGetMessages(res http.ResponseWriter, req *http.Request) {
	json.NewEncoder(res).Encode(&api.Messages)
	api.Messages = []debugMessage{}	
}

func (api *MTADebugAPI) handlerGetBreakpoints(res http.ResponseWriter, req *http.Request) {
	json.NewEncoder(res).Encode(&api.Breakpoints)
}

func (api *MTADebugAPI) handlerSetBreakpoint(res http.ResponseWriter, req *http.Request) {
	breakpoint := debugBreakpoint{}
	err := json.NewDecoder(req.Body).Decode(&breakpoint)

	if err != nil {
		panic(err)
	} else {
		api.Breakpoints = append(api.Breakpoints, breakpoint)
	}
	add_command := debugCommand{"set_breakpoint", []string{breakpoint.File, strconv.Itoa(breakpoint.Line)}}
	api.CommandsServer = append(api.CommandsServer,add_command)
	api.CommandsClient = append(api.CommandsClient,add_command)

	json.NewEncoder(res).Encode(&breakpoint)
}

func (api *MTADebugAPI) handlerRemoveBreakpoint(res http.ResponseWriter, req *http.Request) {
	breakpoint := debugBreakpoint{}
	err := json.NewDecoder(req.Body).Decode(&breakpoint)

	if err != nil {
		panic(err)
	} else {
		newBreakpoints := []debugBreakpoint{}
		for _, bp := range newBreakpoints {
			if bp.equals(&breakpoint) {
				newBreakpoints = append(newBreakpoints, bp)
			}
		}
		api.Breakpoints = newBreakpoints
	}

	json.NewEncoder(res).Encode(&breakpoint)
}

func (api *MTADebugAPI) handlerClearBreakpoints(res http.ResponseWriter, req *http.Request) {
	api.Breakpoints = []debugBreakpoint{}

	json.NewEncoder(res).Encode(&api.Breakpoints)
}

func (api *MTADebugAPI) handlerGetResumeModeServer(res http.ResponseWriter, req *http.Request) {
	json.NewEncoder(res).Encode(&api.ServerContext)
}

func (api *MTADebugAPI) handlerGetResumeModeClient(res http.ResponseWriter, req *http.Request) {
	json.NewEncoder(res).Encode(&api.ClientContext)
}

func (api *MTADebugAPI) handlerSetResumeModeServer(res http.ResponseWriter, req *http.Request) {
	// Create an empty context (Decode merges the structures instead of fully overwriting)
	context := debugContext{}

	err := json.NewDecoder(req.Body).Decode(&context)
	if err != nil {
		panic(err)
	} else {
		api.ServerContext = context
		json.NewEncoder(res).Encode(&api.ServerContext)

		add_command := debugCommand{"set_resume_mode", []string{strconv.Itoa(context.ResumeMode)}}
		api.CommandsServer = append(api.CommandsServer,add_command)
		api.CommandsClient = append(api.CommandsClient,add_command)
	}
}

func (api *MTADebugAPI) handlerSetResumeModeClient(res http.ResponseWriter, req *http.Request) {
	// Create an empty context (Decode merges the structures instead of fully overwriting)
	context := debugContext{}

	err := json.NewDecoder(req.Body).Decode(&context)
	if err != nil {
		panic(err)
	} else {
		api.ClientContext = context
		json.NewEncoder(res).Encode(&api.ClientContext)
	}
}

func (api *MTADebugAPI) handlerGetInfo(res http.ResponseWriter, req *http.Request) {
	err := json.NewEncoder(res).Encode(&api.Info)
	if err != nil {
		panic(err)
	}
}

func (api *MTADebugAPI) handlerSetInfo(res http.ResponseWriter, req *http.Request) {
	err := json.NewDecoder(req.Body).Decode(&api.Info)
	if err != nil {
		panic(err)
	} else {
		if api.Info.ResourcePath != "" {
			// Check if bundle is up to date
			api.MTAServer.UpdateDebugLuaBundle(api.MTAServer.GetResourcePath()+api.Info.ResourcePath+"MTATD.bundle.lua", filepath.Dir(os.Args[0])+"./MTATD.bundle.lua")
		}

		json.NewEncoder(res).Encode(&api.Info)
	}
}
