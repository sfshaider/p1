package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"loggy/config"
	"loggy/dev"
	"loggy/reader"
	"loggy/server"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	if !dev.RunningLocal() {
		fmt.Println("Setting cloudwatch friendly log settings...")
		// add file and line to logs, remove timestamps from logs
		log.SetFlags(log.LstdFlags &^ (log.Ldate | log.Ltime))
	} else {
		log.SetFlags(log.LstdFlags)
	}

	confFile := flag.String("cf", "/home/pay1/etc/loggy.conf", "config file")
	startDaemon := flag.Bool("daemon", false, "run as daemon")
	serverMode := flag.Bool("server", false, "run server mode")
	readerMode := flag.Bool("reader", false, "run reader mode")

	flag.Parse()

	isDaemon := os.Getenv("DAEMON") == "true"

	if *startDaemon {
		*serverMode = true
		*readerMode = false
	}

	if *serverMode && *readerMode {
		log.Fatal("Server and reader modes are mutually exclusive")
	}

	if !*serverMode && !*readerMode {
		log.Fatal("Server or reader mode must be specified")
	}

	cf, ok := config.LoadConfigFile(*confFile)
	if !ok {
		log.Fatal("Failed to read config file")
	}

	if isDaemon {
		server.StartServer(cf)
		return
	}

	if *readerMode {
		log.Printf("Starting reader...\n")
		reader.StartReader(cf)
		return
	}

	if *serverMode {
		sigChan := make(chan os.Signal, 1)
		signal.Notify(sigChan, syscall.SIGQUIT, syscall.SIGKILL)

		timeout, cancelTimeout := context.WithTimeout(context.Background(), time.Second*20)

		go fork()

		log.Printf("Waiting for ready signal from server\n")
		select {
		case <-timeout.Done():
			log.Printf("Timed out waiting for signal from server.  Server may not have started correctly. My pid is %d\n", os.Getpid())
		case sig := <-sigChan:
			switch sig {
			case syscall.SIGQUIT:
				log.Printf("Loggy server started successfully.")
			case syscall.SIGKILL:
				// does not allow for any more code to run, process dies immediately
				// here for completeness
			}
			cancelTimeout()
		}
	}
}

func fork() (pid int, ok bool) {
	var err error
	pid, err = syscall.ForkExec(os.Args[0], os.Args, &syscall.ProcAttr{
		Env: append(os.Environ(), "DAEMON=true", fmt.Sprintf("PARENT=%d", os.Getpid())),
		Sys: &syscall.SysProcAttr{
			Setsid: true,
		},
	})
	if err != nil {
		log.Println(err)
		return
	}

	ok = true

	return
}
