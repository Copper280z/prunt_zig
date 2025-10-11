#!/bin/bash

rm tmp.csv && ./bin/prunt_simulator | tee >(grep -v ".*,.*,.*,.*,,,," >>/dev/stdout) | grep ".*,.*,.*,.*,.*,,,," >tmp.csv
