package server

import (
	"bufio"
	"fmt"
	"io"
	"log"
	"loggy/common"
	"loggy/config"
	"loggy/dev"
	"os"
	"strings"
	"sync"
	"syscall"
	"time"
)

type OutputChannelMessage struct {
	Message   string
	Timestamp time.Time
	Prefix    string
}

func StartServer(cf *config.Config) {
	logFileHandle := setupLogfile(cf)
	defer func() {
		_ = logFileHandle.Close()
	}()

	outputChan := make(chan OutputChannelMessage, 100)

	wg := &sync.WaitGroup{}
	for inputIndex := range cf.Inputs {
		wg.Add(1)
		log.Printf("Creating fifo %s for %s\n", cf.Inputs[inputIndex].FifoFile, cf.Inputs[inputIndex].Name)
		go createAndReadInputFifo(cf, inputIndex, outputChan, wg)
	}

	log.Printf("Waiting for fifos to be created\n")
	wg.Wait()

	ok := common.MakeFifo("output", cf.OutputFifoFile)
	if !ok {
		log.Fatalln("Failed to create output file fifo")
	}

	log.Printf("All fifos created successfully...\n")

	signalParent()

	log.Printf("Starting output channel read loop\n")
	var outputFifo *common.Fifo
	outputFifo = openOutputFifo("output", cf.OutputFifoFile)
	if !ok {
		log.Fatalln("Failed to open output fifo for writing")
	}

	outputFifoWriter := bufio.NewWriter(outputFifo.Writer)

	for {
		message := <-outputChan
		writeLog(message, outputFifoWriter)
	}
}

func writeLog(message OutputChannelMessage, outputFifoWriter *bufio.Writer) {
	message.Message = strings.TrimSuffix(message.Message, "\n")
	outputLine := fmt.Sprintf("[%s] %s\n", message.Prefix, message.Message)
	if dev.RunningLocal() {
		outputLine = fmt.Sprintf("%s %s", message.Timestamp.Format(time.RFC3339), outputLine)
	}

	_, err := outputFifoWriter.WriteString(outputLine)
	if err != nil {
		log.Printf("Failed to write line to output fifo: %s", err.Error())
	}

	_ = outputFifoWriter.Flush()
}

func signalParent() {
	log.Printf("Signaling parent pid %d with SIGQUIT\n", os.Getppid())
	err := syscall.Kill(os.Getppid(), syscall.SIGQUIT)
	if err != nil {
		log.Fatalf("Failed to send signal to parent process: %s\n", err.Error())
	}
}

func setupLogfile(cf *config.Config) (logFileHandle *os.File) {
	logFile := fmt.Sprintf("%s/server.log", cf.BasePath)
	var err error
	logFileHandle, err = os.OpenFile(logFile, os.O_RDWR|os.O_CREATE|os.O_APPEND, 0666)
	if err != nil {
		// no way to log the error
		os.Exit(1)
	}

	log.SetOutput(logFileHandle)

	return
}

func createAndReadInputFifo(cf *config.Config, inputFifoConfigIndex int, outputChan chan OutputChannelMessage, wg *sync.WaitGroup) {
	inputConfig := cf.Inputs[inputFifoConfigIndex]

	defer func() {
		log.Printf("Setup for %s complete\n", inputConfig.Name)
		wg.Done()
	}()

	ok := makeFifoForReading(cf, inputFifoConfigIndex)
	if !ok {
		return
	}

	var fifo *common.Fifo

	name := inputConfig.Name
	fifoPath := common.FifoPath(cf, inputConfig.FifoFile)

	fifo = openInputFifoForReading(fifoPath, name)
	if !ok {
		log.Printf("Failed to open input fifo for reading\n")
		return
	}

	message := fmt.Sprintf("Created fifo %s for %s", inputConfig.FifoFile, inputConfig.Name)
	log.Printf(message)

	go readFifoIntoChannel(cf, inputFifoConfigIndex, fifo.Reader, outputChan)
}

func readFifoIntoChannel(cf *config.Config, inputFifoConfigIndex int, fifo *os.File, outputChannel chan OutputChannelMessage) {
	inputConfig := cf.Inputs[inputFifoConfigIndex]
	reader := bufio.NewReader(fifo)
	for {
		line, err := reader.ReadBytes('\n')
		if err != nil && err != io.EOF {
			log.Printf("fifo read error: %s\n", err.Error())
			log.Fatalf("Failed to read data from fifo %s for %s: %s", inputConfig.FifoFile, inputConfig.Name, err.Error())
		} else if err == io.EOF {
			time.Sleep(time.Second * 1)
			continue
		}

		outputChannel <- OutputChannelMessage{
			Message: string(line),
			Prefix:  inputConfig.LogPrefix,
		}
	}
}

func openInputFifoForReading(fifoPath, name string) (fifo *common.Fifo) {
	fifo = &common.Fifo{}

	go func() {
		openFifoForReading(fifo, fifoPath, name)
	}()

	openFifoForWriting(fifo, fifoPath, name)
	return
}

func openOutputFifo(name string, fifoPath string) (fifo *common.Fifo) {
	fifo = &common.Fifo{}
	openFifoForWriting(fifo, fifoPath, name)
	return
}

func openFifoForReading(fifo *common.Fifo, fifoPath string, name string) {
	var err error
	fifo.Reader, err = os.OpenFile(fifoPath, os.O_RDONLY, os.ModeNamedPipe)
	if err != nil {
		log.Fatalf("Failed to open readerFifo %s for %s for reading: %s", fifoPath, name, err.Error())
	}
}

func openFifoForWriting(fifo *common.Fifo, fifoPath string, name string) {
	var err error
	fifo.Writer, err = os.OpenFile(fifoPath, os.O_WRONLY, os.ModeNamedPipe) // prevents errors by ensuring there is always a writer to the fifo
	if err != nil {
		log.Fatalf("Failed to open readerFifo %s for %s for writing to ensure it stays open: %s", fifoPath, name, err.Error())
	}
}

func makeFifoForReading(cf *config.Config, inputFifoConfigIndex int) (ok bool) {
	inputConfig := cf.Inputs[inputFifoConfigIndex]
	fifoPath := common.FifoPath(cf, inputConfig.FifoFile)
	return common.MakeFifo(inputConfig.Name, fifoPath)
}
