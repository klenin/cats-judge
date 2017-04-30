#!/bin/sh
#export SP_USER=
#export SP_PASSWORD=
export SP_RUNAS=0
export SP_WRITE_LIMIT=30
export SP_MEMORY_LIMIT=256
export SP_DEADLINE=10
export SP_REPORT_FILE=report.txt
export SP_OUTPUT_FILE=stdout.txt
export SP_ERROR_FILE=stderr.txt
export SP_HIDE_REPORT=1
export SP_HIDE_OUTPUT=0
export SP_SECURITY_LEVEL=0
export CATS_JUDGE=1
export SP_LOAD_RATIO=5%
#export SP_LEGACY=sp00
export SP_JSON=1
ABS_PATH="$( echo "$0" | perl -MCwd -lpe '$_ = Cwd::abs_path(-l $_ ? readlink : $_)' )"
DIR="$( cd "$( dirname $ABS_PATH )" && pwd -P )"
perl $DIR/../judge.pl $*
