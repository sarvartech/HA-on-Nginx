#!/bin/bash
# ==============================================================================
# Nginx Process Health Check for Keepalived VRRP
# 0 = Nginx ishlayapti (OK)
# 1 = Nginx to'xtagan (Failover kerak)
# ==============================================================================

if /usr/bin/killall -0 nginx; then
    exit 0
else
    exit 1
fi
