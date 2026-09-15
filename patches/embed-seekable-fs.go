// SPDX-FileCopyrightText: 2025 Free Mobile
// SPDX-License-Identifier: AGPL-3.0-only

// Package embed provides access to the compressed archive containing all the
// embedded files.
//
// PATCH LOCAL (akvorado-for-lazy)
//
// Este arquivo substitui common/embed/fs.go do akvorado v2.0.4 durante o build.
//
// Motivo: o commit b1d6382 do upstream ("common/embed: replace all go:embed use
// by an embedded archive", 02/09/2025) trocou os //go:embed diretos por um unico
// arquivo ZIP embutido. Arquivos abertos de um embed.FS implementam io.Seeker;
// arquivos abertos de um archive/zip NAO implementam (verificado em
// src/archive/zip/reader.go do Go 1.25 e 1.26: o tipo devolvido por Reader.Open
// so tem Read, Close e Stat).
//
// Com isso, todo caminho do net/http que precisa posicionar o conteudo passa a
// falhar com HTTP 500 e corpo "seeker can't seek". Na pratica, o orchestrator
// deixa de servir os CSVs que alimentam os dicionarios do ClickHouse
// (asns.csv, protocols.csv, tcp.csv, udp.csv, icmp.csv). O dicionario "asns"
// fica em FAILED e qualquer consulta do Console que use SrcAS/DstAS estoura,
// aparecendo na UI como "Internal Server Error".
//
// A correcao envolve apenas Data(): os arquivos regulares passam a ser lidos
// para memoria e devolvidos sobre um *bytes.Reader, que implementa io.Seeker.
// Diretorios continuam sendo devolvidos intactos, preservando ReadDir. O
// dataOnce original e o //go:embed seguem inalterados.
//
// Remover este patch quando o upstream corrigir e este repo subir de versao.
package embed

import (
	"archive/zip"
	"bytes"
	_ "embed"
	"fmt"
	"io"
	"io/fs"
	"sync"
)

//go:embed data/embed.zip
var embeddedZip []byte

var dataOnce = sync.OnceValue(func() *zip.Reader {
	r, err := zip.NewReader(bytes.NewReader(embeddedZip), int64(len(embeddedZip)))
	if err != nil {
		panic(fmt.Sprintf("cannot read embedded archive: %s", err))
	}
	return r
})

// Data returns a filesystem with the files contained in the embedded archive.
// Opened regular files also implement io.Seeker, which net/http requires.
func Data() fs.FS {
	return seekableFS{dataOnce()}
}

// seekableFS wraps a filesystem so that opened regular files implement
// io.Seeker, which entries coming straight out of archive/zip do not.
type seekableFS struct {
	fs.FS
}

// Open opens the named file, materialising regular files in memory so that the
// result is seekable. Directories are passed through untouched.
func (s seekableFS) Open(name string) (fs.File, error) {
	f, err := s.FS.Open(name)
	if err != nil {
		return nil, err
	}
	info, err := f.Stat()
	if err != nil {
		f.Close()
		return nil, err
	}
	if info.IsDir() {
		return f, nil
	}
	content, err := io.ReadAll(f)
	f.Close()
	if err != nil {
		return nil, err
	}
	return &seekableFile{Reader: bytes.NewReader(content), info: info}, nil
}

// seekableFile is an fs.File backed by an in-memory buffer. It gets Read and
// Seek from the embedded *bytes.Reader.
type seekableFile struct {
	*bytes.Reader
	info fs.FileInfo
}

// Stat returns the FileInfo carried over from the underlying archive entry.
func (f *seekableFile) Stat() (fs.FileInfo, error) {
	return f.info, nil
}

// Close is a no-op: the underlying archive entry is already closed.
func (f *seekableFile) Close() error {
	return nil
}
