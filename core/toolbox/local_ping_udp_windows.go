//go:build windows

package toolbox

import (
	"net"
	"syscall"
	"unsafe"
)

// Re-enable ICMP port-unreachable reporting (SIO_UDP_CONNRESET) that Go's net
// package disables on Windows UDP sockets so closed UDP ports report "closed"
// instead of timing out.
func enableLocalUDPConnReset(conn net.Conn) {
	sc, ok := conn.(syscall.Conn)
	if !ok {
		return
	}
	raw, err := sc.SyscallConn()
	if err != nil {
		return
	}
	_ = raw.Control(func(fd uintptr) {
		var ret uint32
		flag := uint32(1)
		_ = syscall.WSAIoctl(
			syscall.Handle(fd),
			syscall.SIO_UDP_CONNRESET,
			(*byte)(unsafe.Pointer(&flag)),
			uint32(unsafe.Sizeof(flag)),
			nil,
			0,
			&ret,
			nil,
			0,
		)
	})
}
