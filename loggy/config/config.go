package config

import (
	"gopkg.in/yaml.v3"
	"log"
	"os"
)

type Config struct {
	BasePath string `yaml:"basePath"`
	Inputs   []struct {
		Name      string `yaml:"name"`
		LogPrefix string `yaml:"logPrefix"`
		FifoFile  string `yaml:"fifoFile"`
	} `yaml:"inputs"`
	OutputFifoFile string `yaml:"outputFifoFile"`
	FatalFile      string `yaml:"fatalFile"`
}

func LoadConfigFile(fileName string) (cf *Config, ok bool) {
	fileContent, readOk := readFile(fileName)
	if !readOk {
		return
	}

	cf, ok = parseFileContents(fileContent)
	return
}

func readFile(fileName string) (content []byte, ok bool) {
	var err error
	content, err = os.ReadFile(fileName)
	if err != nil {
		log.Printf("Failed to read config file %s: %s\n", fileName, err.Error())
		return
	}

	ok = true
	return
}

func parseFileContents(content []byte) (cf *Config, ok bool) {
	var err error
	cf = &Config{}
	err = yaml.Unmarshal(content, &cf)
	if err != nil {
		log.Printf("Failed to parse config file contents: %s", err.Error())
		return
	}

	ok = true
	return
}
