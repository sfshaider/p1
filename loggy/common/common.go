package common

import (
	"fmt"
	"log"
	"loggy/config"
	"os"
	"syscall"
)

const ReadyFifo = ".ready"

type Fifo struct {
	Reader *os.File
	Writer *os.File
}

func MakeFifo(name string, fifoPath string) (ok bool) {
	err := syscall.Mkfifo(fifoPath, syscall.O_RDWR)
	if err != nil {
		log.Fatalf("Failed to create fifo at %s for %s: %s", fifoPath, name, err.Error())
	}

	ok = true
	return
}

func ReadyFifoPath(cf *config.Config) string {
	return FifoPath(cf, ReadyFifo)
}

func FifoPath(cf *config.Config, fifoFile string) string {
	return fmt.Sprintf("%s/%s", cf.BasePath, fifoFile)
}

func OpenReadyFifo(cf *config.Config, mode int) *os.File {
	readyFifoPath := ReadyFifoPath(cf)

	readyHandle, err := os.OpenFile(readyFifoPath, mode, os.ModeNamedPipe)
	if err != nil {
		log.Fatalf("Failed to open ready fifo: %s\n", err.Error())
	}

	return readyHandle
}
