package main

import (
	"net/http"
	"os"
	"fmt"

	"github.com/gorilla/mux"
)

func logMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(res http.ResponseWriter, req *http.Request) {
		fmt.Printf("[%s] %s\n", req.Method, req.URL)

		next.ServeHTTP(res, req)
	})
}

func main() {
	// Check args
	if len(os.Args) < 2 {
		fmt.Printf("ERROR: Syntax %s <backend-port>", os.Args[0])
		return
	}

	// Make root router
	router := mux.NewRouter()

	// Initialise APIs
	NewMTADebugAPI(router.PathPrefix("/MTADebug").Subrouter())


	// Start HTTP server
	fmt.Println("Launching HTTP server...")

	http.Handle("/", router) // Handle normally

	// Listen in a secondary goroutine
	http.ListenAndServe(":"+os.Args[1], nil)
}
