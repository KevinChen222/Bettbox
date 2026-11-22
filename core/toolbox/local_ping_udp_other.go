//go:build !windows

package toolbox

import "net"

func enableLocalUDPConnReset(net.Conn) {}
