#!/bin/bash
# Nginx jarayoni mavjudligini tekshiradi (0 = OK, 1 = Error)
if /usr/bin/killall -0 nginx; then
    exit 0
else
    exit 1
fi
