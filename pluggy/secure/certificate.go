package secure

import (
	"crypto/rsa"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/acm"
	"log"
	"math/rand"
	"os"
)

type KeyData struct {
	Key                  string `json:"key"`
	CertificateWithChain string `json:"certificateWithChain"`
	CA                   string `json:"ca"`
}

type Certificate struct {
	CertificateWithChain string
	Key                  string
	CA                   string
}

func LoadCertificate() (err error) {
	var certInfo Certificate
	certInfo, err = loadCertificateFromACM()
	if err != nil {
		return
	}
	// write cert info to disk so gin can use it
	certificate := []byte(certInfo.CertificateWithChain)
	key := []byte(certInfo.Key)

	err = os.WriteFile("/home/pay1/etc/ssl/cert.pem", certificate, 0600)
	if err != nil {
		return
	}

	err = os.WriteFile("/home/pay1/etc/private.pem", []byte(certInfo.CA), 0444)
	var f *os.File
	f, err = os.OpenFile("/etc/ssl/certs/ca-certificates.crt",
		os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		log.Println(err)
	}
	defer f.Close()
	if _, err := f.WriteString(certInfo.CA); err != nil {
		log.Println(err)
	}

	err = os.WriteFile("/home/pay1/etc/ssl/key.pem", key, 0600)

	return
}

func loadCertificateFromACM() (certificateInfo Certificate, err error) {
	region := os.Getenv("AWS_REGION")
	if region == "" {
		region = "us-east-1"
	}

	var sess *session.Session
	sess, err = session.NewSessionWithOptions(session.Options{
		Config: aws.Config{
			Region:                        aws.String(region),
			CredentialsChainVerboseErrors: aws.Bool(true),
		},
		SharedConfigState: session.SharedConfigEnable,
	})

	if err != nil {
		return
	}

	certificateArn := os.Getenv("CERTIFICATE_ARN")
	if certificateArn == "" {
		err = errors.New("variable CERTIFICATE_ARN not defined in environment")
		return
	}

	randomPass := generateRandomPassword(16)

	acmClient := acm.New(sess, aws.NewConfig().WithRegion(region))

	var exportResult *acm.ExportCertificateOutput
	exportResult, err = acmClient.ExportCertificate(&acm.ExportCertificateInput{
		CertificateArn: aws.String(certificateArn),
		Passphrase:     randomPass,
	})
	if err != nil {
		return
	}

	if exportResult.PrivateKey == nil {
		err = errors.New("private key is nil")
		return
	}
	e := []byte(*exportResult.PrivateKey)
	decoded, _ := pem.Decode(e)
	var key interface{}
	key, err = ParsePKCS8PrivateKey(decoded.Bytes, randomPass)
	if err != nil {
		return
	}

	var privKey *rsa.PrivateKey
	var isPrivateKey bool
	privKey, isPrivateKey = key.(*rsa.PrivateKey)
	if !isPrivateKey {
		err = errors.New("parsed private key is invalid")
		return
	}

	privKeyEncoded := pem.EncodeToMemory(
		&pem.Block{
			Type:  "RSA PRIVATE KEY",
			Bytes: x509.MarshalPKCS1PrivateKey(privKey),
		},
	)

	certificateInfo.CertificateWithChain = *exportResult.Certificate + *exportResult.CertificateChain
	certificateInfo.Key = string(privKeyEncoded)

	return
}

func generateRandomPassword(length uint8) (password []byte) {
	const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	password = make([]byte, length)
	for i := range password {
		password[i] = chars[rand.Intn(len(chars))]
	}
	return password
}
