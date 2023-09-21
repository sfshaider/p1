package main

import (
	"crypto/tls"
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"os"
	"pluggy/secure"
	"time"
)

func main() {
	runHealthcheckArg := flag.Bool("healthcheck", false, "run healthcheck")
	getCertArg := flag.Bool("getcert", false, "get certificate")
	flag.Parse()

	if *runHealthcheckArg {
		healthcheck()
	} else if *getCertArg {
		getCert()
	}
}

func getCert() {
	fmt.Println("Retrieving certificate")
	err := secure.LoadCertificate()
	if err != nil {
		log.Println("failed to retrieve certificate: ", err.Error())
	}
}

func healthcheck() {
	fmt.Println("Running healthcheck...")
	insecure := http.DefaultTransport.(*http.Transport).Clone()
	insecure.TLSClientConfig = &tls.Config{InsecureSkipVerify: true} // ok for healthcheck to localhost
	cl := http.Client{
		Transport: insecure,
		Timeout:   time.Second * 15,
	}
	resp, err := cl.Get("https://localhost/healthcheck/")
	if err != nil {
		fmt.Println("Failed to call healthcheck: ", err.Error())
		os.Exit(1)
	}
	if resp.StatusCode != http.StatusOK {
		var body []byte
		body, err = ioutil.ReadAll(resp.Body)
		if err != nil {
			fmt.Println("Failed to read healthcheck response: ", err.Error())
			os.Exit(1)
		} else {
			fmt.Println("Healthcheck failed with message: ", string(body))
			os.Exit(1)
		}
	}
	fmt.Println("OK")
}
