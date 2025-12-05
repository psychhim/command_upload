#!/bin/bash
echo "START"
if ! -t 0; then
    echo "STDIN is NOT a tty"
    cat
else
    echo "STDIN *IS* a tty"
fi
echo "END"
