package main

import (
	"fmt"
	"net/http"
)

func main() {
	fmt.Println("Starting")
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Println("/ called")
		w.Write([]byte("Hello World"))
	})
	err := http.ListenAndServe(":8080", nil)
	if err != nil {
		panic(err)
	}
	fmt.Println("Server is running on port 8080")
}
