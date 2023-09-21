package reader

import (
	"bufio"
	"fmt"
	"log"
	"loggy/common"
	"loggy/config"
	"os"
)

func StartReader(cf *config.Config) {
	outputFifo, ok := openFifoForReading("output", cf.OutputFifoFile)
	if !ok {
		log.Fatalln("Failed to open output fifo")
	}

	fifoReader := bufio.NewReader(outputFifo.Reader)

	for {
		data, err := fifoReader.ReadBytes('\n')
		if err != nil {
			log.Fatalln("Failed to read output fifo")
		}
		// ReadBytes *includes* the delimiter, so no need to add a \n here
		log.Print(string(data))
	}
}

func openFifoForReading(name string, fifoPath string) (fifo *common.Fifo, ok bool) {
	var err error

	fifo = &common.Fifo{}

	fifo.Reader, err = os.OpenFile(fifoPath, os.O_RDONLY, os.ModeNamedPipe)
	if err != nil {
		message := fmt.Sprintf("Failed to open readerFifo %s for %s for reading: %s", fifoPath, name, err.Error())
		log.Printf(message)
		return
	}

	ok = true
	return
}
