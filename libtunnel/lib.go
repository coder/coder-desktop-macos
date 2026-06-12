//go:build darwin

// Package main builds the Coder Connect tunnel as a C archive, so it can be
// statically linked into the iOS Network Extension. iOS forbids downloading
// and executing code at runtime (App Store Guideline 2.5.2), so unlike the
// macOS LaunchDaemon, which downloads and spawns the deployment's `coder`
// binary, the tunnel is compiled into the app at build time.
//
// This resurrects the entry point removed from coder/coder in
// https://github.com/coder/coder/pull/22592.
package main

import "C"

import (
	"context"

	"golang.org/x/sys/unix"

	"cdr.dev/slog"

	"github.com/coder/coder/v2/vpn"
)

const (
	ErrDupReadFD  = -2
	ErrDupWriteFD = -3
	ErrOpenPipe   = -4
	ErrNewTunnel  = -5
)

// OpenTunnel creates a new VPN tunnel by `dup`ing the provided 'PIPE'
// file descriptors for reading and writing. The tunnel speaks the
// `vpn.proto` manager/tunnel protocol over these descriptors, and runs
// until the write end is closed.
//
//export OpenTunnel
func OpenTunnel(cReadFD, cWriteFD int32) int32 {
	ctx := context.Background()

	readFD, err := unix.Dup(int(cReadFD))
	if err != nil {
		return ErrDupReadFD
	}

	writeFD, err := unix.Dup(int(cWriteFD))
	if err != nil {
		unix.Close(readFD)
		return ErrDupWriteFD
	}

	conn, err := vpn.NewBidirectionalPipe(uintptr(readFD), uintptr(writeFD))
	if err != nil {
		unix.Close(readFD)
		unix.Close(writeFD)
		return ErrOpenPipe
	}

	// We log everything, as filtering is done by whatever renders the OS
	// logs.
	_, err = vpn.NewTunnel(ctx, slog.Make().Leveled(slog.LevelDebug), conn,
		vpn.NewClient(),
		vpn.UseOSNetworkingStack(),
		vpn.UseAsLogger(),
	)
	if err != nil {
		unix.Close(readFD)
		unix.Close(writeFD)
		return ErrNewTunnel
	}

	return 0
}

func main() {}
