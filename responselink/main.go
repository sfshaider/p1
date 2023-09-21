package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"flag"
	"fmt"
	"github.com/gin-gonic/gin"
	"github.com/miekg/dns"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"runtime"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

func main() {
	log.SetFlags((log.LstdFlags | log.Lshortfile) &^ (log.Ldate | log.Ltime))

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, syscall.SIGQUIT, syscall.SIGTERM, syscall.SIGINT) // SIGKILL doesn't allow you to do anything before killing

	var logBasePathFlag = flag.String("logbase", "", "Set the log directory")
	var pidFileNameFlag = flag.String("pidfile", "responselink.pid", "Set the location of the pid file, default is in the log directory")
	var doHealthcheckFlag = flag.Bool("healthcheck", false, "Run healthcheck and exist")
	var daemonFlag = flag.Bool("daemon", false, "Run daemon mode directly")

	flag.Parse()
	if *logBasePathFlag == "" {
		log.Fatalln("Error: --logbase must be set.")
	}

	if *doHealthcheckFlag {
		healthcheck()
		return
	}

	logBasePath := *logBasePathFlag
	// remove trailing slashes from logBasePath
	if logBasePath != "" {
		rIndex := len(logBasePath)
		for rIndex >= 1 && logBasePath[rIndex-1:rIndex] == "/" {
			rIndex = rIndex - 1
		}
	}

	err := os.Chdir(logBasePath)
	if err != nil {
		log.Fatalf("Failed to change directories to %s: %s\n", logBasePath, err.Error())
	}

	isDaemon := os.Getenv("DAEMON") == "true"
	pidFilePathName := *pidFileNameFlag

	if !*daemonFlag && !isDaemon {
		// the following function e
		exitCode := startDaemon(pidFilePathName)
		os.Exit(exitCode)
	}

	//create PID file in log directory
	pidFile, success := createPidFile(pidFilePathName, os.Getpid())
	if !success {
		log.Printf("Exiting...")
		os.Exit(1)
	} else {
		go removePidFileOnSignal(pidFile, sigChan)
	}

	var logFile *os.File
	logFile, err = openLog(fmt.Sprintf("%s/responselink.log", logBasePath))

	if err != nil {
		log.Fatalln("Failed to create error log.")
	}

	log.SetFlags(log.LstdFlags | log.Lshortfile)
	log.SetOutput(logFile)

	wg := sync.WaitGroup{}
	wg.Add(1)
	go restartServer(&wg)
	wg.Wait()
}

func startDaemon(pidFilePathName string) (exitCode int) {
	alreadyRunning, stalePidFile, success := preForkCheck(pidFilePathName)
	if !success {
		exitCode = 1
		return
	}

	// if already running, it's all good, because that's what we wanted
	if alreadyRunning {
		exitCode = 0
		return
	}

	// if there is a stale pid file, we want to remove it
	if stalePidFile {
		removed := removePidFile(pidFilePathName)
		if !removed {
			log.Printf("Failed to remove stale pid file")
			exitCode = 1
			return
		}
	}

	var pid int
	pid, success = fork(pidFilePathName)
	if !success {
		log.Printf("Failed to fork!\n")
		exitCode = 1
		return
	}

	log.Printf("Started daemon with pid %d\n", pid)
	exitCode = 0

	return
}

func preForkCheck(pidFilePathName string) (alreadyRunning bool, stalePidFile bool, success bool) {
	pidFileContent, err := os.ReadFile(pidFilePathName)

	// if the file does not exist, return, as both alreadyRunning and stalePidFile would be false
	if os.IsNotExist(err) {
		success = true
		return
	}

	pidFileContentString := string(pidFileContent)
	pidFileContentString = strings.Replace(pidFileContentString, "\n", "", -1)

	// get the pid from the file
	var pid int64
	pid, err = strconv.ParseInt(pidFileContentString, 10, 64)
	if err != nil {
		log.Printf("Failed to parse pid in pid file: %s\n", err.Error())
		return
	}

	switch runtime.GOOS {
	case "linux":
		procDirectory := fmt.Sprintf("/proc/%d/", pid)
		_, err := os.Stat(procDirectory)
		if os.IsNotExist(err) {
			stalePidFile = true
			success = true
		} else if err != nil {
			log.Printf("Error while reading /proc to determine if process is already running\n")
		} else {
			alreadyRunning = true
			success = true
		}
	default:
		log.Printf("Pid file present, unsupported runtime OS for safe start\n")
	}

	return
}

func fork(pidFilePathName string) (pid int, ok bool) {
	_, err := os.Stat(pidFilePathName)
	if os.IsNotExist(err) {
		pid, err = syscall.ForkExec(os.Args[0], os.Args, &syscall.ProcAttr{
			Env: append(os.Environ(), "DAEMON=true"),
			Sys: &syscall.SysProcAttr{
				Setsid: true,
			},
		})
		if err != nil {
			log.Println(err)
			return
		}

		// this is not really an error condition, so we don't want to return false
		ok = true
	} else if err != nil {
		log.Printf("Error trying to stat pidfile: %s\n", err.Error())
	} else {
		log.Println("Pid file exists, perhaps the daemon is already running?")
	}

	return
}

func createPidFile(pidFilePathName string, pid int) (pidFile *os.File, success bool) {
	var err error
	pidFile, err = os.OpenFile(pidFilePathName, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0644)
	if err != nil {
		log.Printf("Failed to create pid file, error: %s\n", err.Error())
		return
	} else {
		_, err = pidFile.WriteString(fmt.Sprintf("%d\n", pid))
		if err != nil {
			log.Printf("Failed to write pid to pid file, error: %s\n", err.Error())
			return
		}
		_ = pidFile.Close()
	}

	success = true
	return
}

func removePidFileOnSignal(pidFile *os.File, sigChan chan os.Signal) {
	for sig := range sigChan {
		if sig == syscall.SIGTERM || sig == syscall.SIGINT || sig == syscall.SIGKILL || sig == syscall.SIGQUIT {
			log.Printf("process %d exiting on signal %s\n", os.Getpid(), sig.String())
			removePidFile(pidFile.Name())
			os.Exit(0)
		}
	}
}

func removePidFile(pidFile string) (success bool) {
	err := os.Remove(pidFile)
	if err != nil {
		log.Printf("failed to remove pid file: %s\n", err.Error())
		return
	}

	success = true
	return
}

func restartServer(wg *sync.WaitGroup) {
	// catch panics in startServer and recover and restart another server
	defer func() {
		r := recover()
		if r != nil {
			// restart server
			log.Printf("Panic recovered: %s\n", r)
			wg.Add(1) // add it back to waitgroup
			go restartServer(wg)
		}
	}()
	startServer(wg)
}

func startServer(wg *sync.WaitGroup) {
	defer wg.Done()
	if os.Getenv("DEVELOPMENT") != "TRUE" {
		gin.SetMode(gin.ReleaseMode)
	}

	engine := gin.New()

	err := engine.SetTrustedProxies(nil)
	if err != nil {
		log.Fatalln("Failed to set trusted proxies: ", err.Error())
	}

	insecureClient := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				InsecureSkipVerify: true,
				VerifyPeerCertificate: func(rawCerts [][]byte, verifiedChains [][]*x509.Certificate) error {
					return nil
				},
			},
			DialContext: getDialContextFunc(time.Second*5, time.Second*5),
		},
	}

	secureClient := &http.Client{
		Transport: &http.Transport{
			DialContext: getDialContextFunc(time.Second*5, time.Second*5),
		},
	}

	// healthcheck
	engine.GET("/healthcheck", healthcheckHandler)
	engine.POST("/proxy", responseLinkHandler(insecureClient, secureClient))

	// *only* run on localhost
	err = engine.Run(":8080")
	if err != nil {
		log.Fatalln("Failed to start gin: ", err.Error())
	}
}

func healthcheck() {
	_, err := http.Get("http://127.0.0.1/healthcheck")
	if err != nil {
		fmt.Println(err.Error())
		os.Exit(1)
	}
	os.Exit(0)
}

func healthcheckHandler(ctx *gin.Context) {
	ctx.String(200, "ok")
	ctx.Done()
}

func openLog(fileName string) (file *os.File, err error) {
	return os.OpenFile(fileName, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
}

func getDialContextFunc(dialTimeout time.Duration, keepAliveTimeout time.Duration) func(ctx context.Context, network string, addr string) (net.Conn, error) {
	return func(ctx context.Context, network string, addr string) (net.Conn, error) {
		dialer := &net.Dialer{
			Timeout:   dialTimeout,
			KeepAlive: keepAliveTimeout,
		}

		ipv4, err := resolveIPv4(addr)
		if err != nil {
			return nil, err
		}

		return dialer.DialContext(ctx, network, ipv4)
	}
}

func resolveIPv4(addr string) (string, error) {
	url := strings.Split(addr, ":")

	m := new(dns.Msg)
	m.SetQuestion(dns.Fqdn(url[0]), dns.TypeA)
	m.RecursionDesired = true

	// this error is ignored intentionally
	config, _ := dns.ClientConfigFromFile("/etc/resolv.conf")
	c := new(dns.Client)
	r, _, err := c.Exchange(m, net.JoinHostPort(config.Servers[0], config.Port))
	if err != nil {
		return "", err
	}
	for _, ans := range r.Answer {
		if a, ok := ans.(*dns.A); ok {
			url[0] = a.A.String()
		}
	}

	return strings.Join(url, ":"), nil
}
