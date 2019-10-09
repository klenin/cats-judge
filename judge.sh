#!/bin/sh

# export ASAN_OPTIONS=verbosity=1

while true
do
    perl judge.pl serve
    sleep 1
done
