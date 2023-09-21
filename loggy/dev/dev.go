package dev

import "os"

func RunningInDevelopment() bool {
	return os.Getenv("DEVELOPMENT") == "TRUE"
}

func RunningLocal() bool {
	return os.Getenv("LOCAL") == "TRUE"
}
