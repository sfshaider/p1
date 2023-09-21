package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"errors"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

type ResponseLinkInput struct {
	Method         string              `json:"method"`
	Url            string              `json:"url"`
	Headers        map[string][]string `json:"headers"`
	ContentType    *string             `json:"contentType"`
	Content        *string             `json:"content"`
	Insecure       bool                `json:"insecure"`
	TimeoutSeconds float64             `json:"timeoutSeconds"`
}

type ResponseLinkOutput struct {
	RequestId    string              `json:"requestId"`
	Error        bool                `json:"error"`
	ErrorMessage *string             `json:"errorMessage"`
	Headers      map[string][]string `json:"headers"`
	StatusCode   int                 `json:"statusCode"`
	Status       string              `json:"status"`
	Content      string              `json:"content"`
}

func responseLinkHandler(insecureClient *http.Client, secureClient *http.Client) func(*gin.Context) {
	return func(ctx *gin.Context) {
		requestId := uuid.NewString()

		output := ResponseLinkOutput{
			RequestId: requestId,
		}

		input := ResponseLinkInput{}
		err := ctx.BindJSON(&input)
		if err != nil {
			log.Printf("incorrect input format: %s\n", err)

			errorMessage := "incorrect input format"

			output.Error = true
			output.ErrorMessage = &errorMessage

			ctx.JSON(http.StatusBadRequest, output)
			return
		}

		err = validateRequest(&input)
		if err != nil {
			log.Printf("error in request for request id %s: %s\n", requestId, err.Error())

			errorMessage := "error in request input"

			output.Error = true
			output.ErrorMessage = &errorMessage

			ctx.JSON(http.StatusBadRequest, output)
			return
		}

		var httpClient *http.Client
		if input.Insecure {
			httpClient = insecureClient
		} else {
			httpClient = secureClient
		}

		statusCode, status, body, headers, success := doRequest(httpClient, &input, requestId)
		if !success {
			errorMessage := "error performing http request"

			output.Error = true
			output.ErrorMessage = &errorMessage

			ctx.JSON(http.StatusInternalServerError, output)
			return
		}

		output.Headers = headers
		output.Content = base64.StdEncoding.EncodeToString(body)
		output.StatusCode = statusCode
		output.Status = status

		ctx.JSON(http.StatusOK, output)
	}
}

func validateRequest(request *ResponseLinkInput) (err error) {
	if request == nil {
		err = errors.New("request is nil")
		return
	}

	if request.Url == "" {
		err = errors.New("request url is blank")
		return
	}

	if request.TimeoutSeconds < 0 {
		err = errors.New("timeout is negative")
		return
	}

	return
}

func doRequest(httpClient *http.Client, input *ResponseLinkInput, requestId string) (statusCode int, status string, body []byte, headers map[string][]string, success bool) {
	if input == nil {
		logMessage("error for request id %s: input is nil\n", requestId)
		return
	}

	// default to 30 second timeout if timeout is zero
	timeout := time.Second * 30

	if input.TimeoutSeconds != 0 {
		timeout = time.Second * time.Duration(input.TimeoutSeconds)
	}

	// create a timeout context for the requests
	timeoutContext, cancelFunc := context.WithTimeout(context.Background(), timeout)
	defer cancelFunc()

	var httpRequest *http.Request
	method := strings.ToUpper(input.Method)
	var err error

	if input.Content != nil {
		var b []byte
		b, err = base64.StdEncoding.DecodeString(*input.Content)
		if err != nil {
			logMessage("an error occured decoding request for request id %s: %s\n", requestId, err.Error())
			return
		}
		httpRequest, err = http.NewRequestWithContext(timeoutContext, method, input.Url, bytes.NewBuffer(b))
		if err != nil {
			logMessage("failed to create http request with content: %s", err.Error())
			return
		}
	} else {
		httpRequest, err = http.NewRequestWithContext(timeoutContext, method, input.Url, nil)
		if err != nil {
			logMessage("failed to create http request without content: %s", err.Error())
			return
		}
	}

	if input.ContentType != nil {
		input.Headers["content-type"] = []string{*input.ContentType}
	} else {
		input.Headers["content-type"] = []string{"application/json"}
	}

	var userAgentSet bool
	for k, _ := range input.Headers {
		if strings.ToLower(k) == "user-agent" {
			userAgentSet = true
		}
	}

	httpRequest.Header = input.Headers

	if !userAgentSet {
		httpRequest.Header.Set("user-agent", "ResponseLinkLocalProxy/1.1")
	}

	start := time.Now()

	var httpResponse *http.Response
	httpResponse, err = httpClient.Do(httpRequest)
	if err != nil {
		logMessage("an error occurred for request id %s: %s\n", requestId, err.Error())
		return
	}

	defer func() {
		_ = httpResponse.Body.Close()
	}()

	body, err = io.ReadAll(httpResponse.Body)
	if err != nil {
		logMessage("failed to read response body for request id %s: %s\n", requestId, err.Error())
		return
	}

	elapsed := time.Since(start)
	headers = httpResponse.Header
	statusCode = httpResponse.StatusCode
	status = httpResponse.Status
	success = true

	logMessage("requestId %s: method: %s, url: %s, duration: %s, status %s\n", requestId, input.Method, input.Url, elapsed, status)

	return
}

func logMessage(format string, v ...any) {
	if _, err := os.Stat("logging_enabled"); err == nil {
		log.Printf(format, v...)
	}
}
