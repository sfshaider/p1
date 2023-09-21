package secure

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/des"
	"encoding/asn1"
)

type cipherWithBlock struct {
	oid      asn1.ObjectIdentifier
	ivSize   int
	keySize  int
	newBlock func(key []byte) (cipher.Block, error)
}

func (c cipherWithBlock) IVSize() int {
	return c.ivSize
}

func (c cipherWithBlock) KeySize() int {
	return c.keySize
}

func (c cipherWithBlock) OID() asn1.ObjectIdentifier {
	return c.oid
}

func (c cipherWithBlock) Encrypt(key, iv, plaintext []byte) ([]byte, error) {
	block, err := c.newBlock(key)
	if err != nil {
		return nil, err
	}
	return cbcEncrypt(block, key, iv, plaintext)
}

func (c cipherWithBlock) Decrypt(key, iv, ciphertext []byte) ([]byte, error) {
	block, err := c.newBlock(key)
	if err != nil {
		return nil, err
	}
	return cbcDecrypt(block, key, iv, ciphertext)
}

func cbcEncrypt(block cipher.Block, key, iv, plaintext []byte) ([]byte, error) {
	mode := cipher.NewCBCEncrypter(block, iv)
	paddingLen := block.BlockSize() - (len(plaintext) % block.BlockSize())
	ciphertext := make([]byte, len(plaintext)+paddingLen)
	copy(ciphertext, plaintext)
	copy(ciphertext[len(plaintext):], bytes.Repeat([]byte{byte(paddingLen)}, paddingLen))
	mode.CryptBlocks(ciphertext, ciphertext)
	return ciphertext, nil
}

func cbcDecrypt(block cipher.Block, key, iv, ciphertext []byte) ([]byte, error) {
	mode := cipher.NewCBCDecrypter(block, iv)
	plaintext := make([]byte, len(ciphertext))
	mode.CryptBlocks(plaintext, ciphertext)
	// TODO: remove padding
	return plaintext, nil
}

var (
	oidAES128CBC = asn1.ObjectIdentifier{2, 16, 840, 1, 101, 3, 4, 1, 2}
	oidAES128GCM = asn1.ObjectIdentifier{2, 16, 840, 1, 101, 3, 4, 1, 6}
	oidAES192CBC = asn1.ObjectIdentifier{2, 16, 840, 1, 101, 3, 4, 1, 22}
	oidAES192GCM = asn1.ObjectIdentifier{2, 16, 840, 1, 101, 3, 4, 1, 26}
	oidAES256CBC = asn1.ObjectIdentifier{2, 16, 840, 1, 101, 3, 4, 1, 42}
	oidAES256GCM = asn1.ObjectIdentifier{2, 16, 840, 1, 101, 3, 4, 1, 46}
)

func init() {
	RegisterCipher(oidAES128CBC, func() Cipher {
		return AES128CBC
	})
	RegisterCipher(oidAES128GCM, func() Cipher {
		return AES128GCM
	})
	RegisterCipher(oidAES192CBC, func() Cipher {
		return AES192CBC
	})
	RegisterCipher(oidAES192GCM, func() Cipher {
		return AES192GCM
	})
	RegisterCipher(oidAES256CBC, func() Cipher {
		return AES256CBC
	})
	RegisterCipher(oidAES256GCM, func() Cipher {
		return AES256GCM
	})
}

// AES128CBC is the 128-bit key AES cipher in CBC mode.
var AES128CBC = cipherWithBlock{
	ivSize:   aes.BlockSize,
	keySize:  16,
	newBlock: aes.NewCipher,
	oid:      oidAES128CBC,
}

// AES128GCM is the 128-bit key AES cipher in GCM mode.
var AES128GCM = cipherWithBlock{
	ivSize:   aes.BlockSize,
	keySize:  16,
	newBlock: aes.NewCipher,
	oid:      oidAES128GCM,
}

// AES192CBC is the 192-bit key AES cipher in CBC mode.
var AES192CBC = cipherWithBlock{
	ivSize:   aes.BlockSize,
	keySize:  24,
	newBlock: aes.NewCipher,
	oid:      oidAES192CBC,
}

// AES192GCM is the 912-bit key AES cipher in GCM mode.
var AES192GCM = cipherWithBlock{
	ivSize:   aes.BlockSize,
	keySize:  24,
	newBlock: aes.NewCipher,
	oid:      oidAES192GCM,
}

// AES256CBC is the 256-bit key AES cipher in CBC mode.
var AES256CBC = cipherWithBlock{
	ivSize:   aes.BlockSize,
	keySize:  32,
	newBlock: aes.NewCipher,
	oid:      oidAES256CBC,
}

// AES256GCM is the 256-bit key AES cipher in GCM mode.
var AES256GCM = cipherWithBlock{
	ivSize:   aes.BlockSize,
	keySize:  32,
	newBlock: aes.NewCipher,
	oid:      oidAES256GCM,
}

var (
	oidDESEDE3CBC = asn1.ObjectIdentifier{1, 2, 840, 113549, 3, 7}
)

func init() {
	RegisterCipher(oidDESEDE3CBC, func() Cipher {
		return TripleDESCBC
	})
}

// TripleDESCBC is the 168-bit key 3DES cipher in CBC mode.
var TripleDESCBC = cipherWithBlock{
	ivSize:   des.BlockSize,
	keySize:  24,
	newBlock: des.NewTripleDESCipher,
	oid:      oidDESEDE3CBC,
}
