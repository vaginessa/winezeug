#!/bin/sh
#
# Wine build-helper script
#
# Copyright 2009 Austin English <austinenglish@gmail.com>
#
# Redistribution and use in source and binary forms, with or without modification, are
# permitted provided that the following conditions are met:
#
#  1. Redistributions of source code must retain the above copyright notice, this list of
#  conditions and the following disclaimer.
#
#  2. Redistributions in binary form must reproduce the above copyright notice, this list of
#  conditions and the following disclaimer in the documentation and/or other materials
#  provided with the distribution.
#
#  THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND ANY EXPRESS OR
#  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
#  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
#  AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
#  OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
#  OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
#  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
#  NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
#  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
#
# To do:
# handle errors gracefully with proper exits and error messages
# test on other OS's
# make sure script is portable
# add more Linux distro support
# OS X support
# Allow $1 arguments. E.g., with no arguments, fetch newtree/build/get winetest/run regular test
# With $1, allow nowin16, win64, +heap, +all, +relay, +message, nogecko, etc.
# Add support for first time git initialization.

# Now some common definitions:

# This WINEPREFIX is for running the conformance tests. If you want to use a
# different one, change it here or override the environmental variable.
WINEPREFIX=${WINEPREFIX:-$HOME/.wine}

# Set your name here. It will be used to submit test data. If none is given, your username will be used.
NAME=${NAME:-`whoami`}

# Set your machine name here. Again, used for the test data. If none is given, your hostname is used.
MACHINE=${MACHINE:-`uname -n`}

# This is the time between retrying to fetch the updated git tree. Default is 30 minutes. Adjust to your taste.
# Be sure you put it in seconds. Not all OS's support the d/h/m options (OpenSolaris, I'm looking at you!)
WAITTIME=1800

# This is simply a placeholder function to workaround the lack of wget on some OS's (the BSD's)
GET=${GET:-`wget -c`}

die() {
  echo "$@"
  exit 1
}

export WINE='`pwd`/wine'

set -ex

# First, find out the OS we're on. This way, we can have on monolithic, yet portable, build script.
# TODO: Find something more portable... `uname -o` fails on FreeBSD, possibly others. Does -s work on Solaris?

OS=`uname -o` || OS=`uname -s`
echo $OS

# TODO: Differentiate between Solaris and OpenSolaris here...not sure how though :-/
if [ $OS = 'Solaris' ]
    then
        CFLAGS="-I/usr/sfw/include -I/usr/X11/include -g" 
        CPPFLAGS="-I/usr/sfw/include" 
        CC="/usr/gnu/bin/cc" 
        LDFLAGS="-L/usr/sfw/lib -R/usr/sfw/lib -L/usr/X11/lib -R/usr/X11/lib" 
        LD="/usr/gnu/bin/ld" 
        PATH="/usr/gnu/bin:/usr/bin:/usr/X11/bin:/usr/sbin:/sbin:/opt/csw/bin/:/usr/ccs/bin:/usr/sfw/bin:/usr/local/bin"
        CONFIGUREFLAGS="--without-ldap --without-capi"
elif [ $OS = 'Linux' ] || [ $OS = 'GNU/Linux' ]
    then
# Unused at the moment, but if there's a distro requiring a strange build setup, this will be useful.
#       distro=`lsb_release -i -r -s`
        echo "Most Linux distros should build fine out of the box."
        echo "If not, please notifiy the maintainer to add your build script here."
elif [ $OS = 'FreeBSD' ]
    then
        CC="ccache gcc"
        CPPFLAGS="-I/usr/local/include"
        LDFLAGS="-L/usr/local/lib"
elif [ $OS = 'NetBSD' ]
    then
        echo "This is untested...going from memory"
        CFLAGS="-O2 -I/usr/pkg/include -I/usr/include -I/usr/pkg/include/freetype2 -I/usr/X11R6/include"
        CPPFLAGS="-I/usr/pkg/include -I/usr/include -I/usr/pkg/include/freetype2 -I/usr/X11R6/include"
        LDFLAGS="-L/usr/pkg/lib -Wl,-R/usr/pkg/lib -L/usr/lib -Wl,-R/usr/lib -L/usr/X11R6/lib -Wl,-R/usr/X11R6/lib"
elif [ $OS = 'OpenBSD' ]
    then
        CFLAGS="-I/usr/local/include -I/usr/local/include/libpng"
        LDFLAGS="-lm -lz -lcrypto -L/usr/local/lib"
        X_EXTRA_LIBS="-lXau -lXdmcp"
        CPPFLAGS="-I/usr/local/include"
else
    echo "Your OS is not supported by this build script. Please e-mail the maintainer if you get this message."
    exit 1
fi

# Make sure wget is available:
if [ `which wget` ]
    then
        GET="wget"
# If not, use ftp. TODO: Find a better fix. This doesn't work on Ubuntu's ftp, possibly others. The only reason
# to use this is for machines that don't have wget. The only ones I've seen that on is the BSD's, and this works fine there.
elif [ `which ftp` ]
    then
        GET="ftp"
else
    echo "You don't have wget or ftp installed. I can't download needed files. Please report this as a bug."
    exit 1
fi

# Fetch an updated tree
newtree() {
# make sure we're in a git tree to start with:
git show > /dev/null 2>&1 || die "Not in a git tree! Initializing a fresh git tree isn't yet supported."
# TODO: don't force a hard reset for those that don't want it. 'git checkout -f origin' should be just as effective 
echo "Resetting git tree to origin." && git reset --hard origin &&
# This is used for our loop to check for updated git tree. TODO: Is there a cleaner way to do this?
TREESTATUS=0
while [ $TREESTATUS = "0" ]
do
  echo "Attempting to fetch updated tree." && git fetch ;
  echo "Applying new patches." ;
# TODO: This fails if the the git site can't be reached. Need to adjust appropriately.
  git rebase origin 2>&1 | grep "Current branch HEAD is up to date" || break
  sleep $WAITTIME
done
}

# If our build fails :'(
build_failed() {
echo "$BUILDNAME build failed for some reason...Investigate manually you lazy bastard!"
exit 1
}

# TODO: sed/grep -v out visibility attribute/ignored return value errors, then wc -l error/warnings lines.
# From there, we can store $WARNINGS_PREDICTED in each OS above, and complain if it doesn't match.
# This shouldn't be used on Ubuntu right now, until the "ignoring return value" problem is fixed.
# TODO: determine if logs are wanted, and if so, store in distclean-date, configure-date, etc.
build() {
echo "Starting $BUILDNAME build." && 
echo "Running make distclean." && make distclean 1>/dev/null 2>&1 ;
echo "Running configure." && ./configure $CONFIGUREFLAGS 1>/dev/null 2>&1 &&
echo "Running make depend." && make depend 1>/dev/null 2>&1 &&
echo "Running make." && make 1>/dev/null 2>&1 &&
echo "$BUILDNAME build was fine. Coolio"
}

# Test functions here...
enable_virtual_desktop() {
echo "Enabling virtual desktop" && 
cat > /tmp/virtualdesktop.reg <<_EOF_
REGEDIT4

[HKEY_CURRENT_USER\Software\Wine\Explorer]
"Desktop"="Default"

[HKEY_CURRENT_USER\Software\Wine\Explorer\Desktops]
"Default"="800x600"
_EOF_
echo "Importing registry key" &&
./wine regedit /tmp/virtualdesktop.reg &&
echo "sleeping for 10 seconds...regedit bug?" && sleep 10s
}

# TODO: get winetest-SHA1SUM. If not available, wait 30 minutes?
get_tests_32() {
    rm -rf winetest-*.exe ;
    $GET http://test.winehq.org/builds/winetest-latest.exe
}

get_tests_64() {
    rm -rf winetest64-*.exe ;
    $GET http://test.winehq.org/builds/winetest64-latest.exe
}

preptests() {
    ./server/wineserver -k || true
    rm -rf $WINEPREFIX winetricks || true
    $GET "http://winezeug.googlecode.com/svn/trunk/winetricks" &&
    sh winetricks gecko > /dev/null 2>&1 || exit 1
}

# TODO: fix to use the SHA1SUM as well.
runtests() {
    echo "About to start $NAME-$MACHINE$TESTNAME test run. Expect no output for a while..." &&
    ./wine winetest-latest.exe -c -t $NAME-$MACHINE$TESTNAME 1>/dev/null 2>&1 &&
    rm -rf $WINEPREFIX
}

all_test() {
WINEDEBUG="+all"
TESTNAME="-all"
export WINEDEBUG
export TESTNAME
preptests
runtests
}

build_regular() {
BUILDNAME=regular
CONFIGUREFLAGS=""
build || build_failed
}

build_nowin16() {
BUILDNAME=nowin16
CONFIGUREFLAGS="--disable-win16"
build || build_failed
}

build_win64() {
BUILDNAME=win64
CONFIGUREFLAGS="--enable-win64"
build || build_failed
}

heap_test() {
WINEDEBUG="warn+heap"
TESTNAME="-heap"
export WINEDEBUG
export TESTNAME
preptests
runtests
}

message_test() {
WINEDEBUG="+message"
TESTNAME="-message"
export WINEDEBUG
export TESTNAME
preptests
runtests
}

nowin16_test() {
WINEDEBUG=""
TESTNAME="-nowin16"
export WINEDEBUG
export TESTNAME
preptests
runtests
}

regular_test() {
WINEDEBUG=""
TESTNAME=""
export WINEDEBUG
export TESTNAME
preptests
runtests
}

relay_test() {
WINEDEBUG="+relay"
TESTNAME="-relay"
export WINEDEBUG
export TESTNAME
preptests
runtests
}

seh_test() {
WINEDEBUG="+seh"
TESTNAME="-seh"
export WINEDEBUG
export TESTNAME
preptests
runtests
}

virtual_desktop_test() {
WINEDEBUG=""
TESTNAME="-virtdesktop"
export WINEDEBUG
export TESTNAME
preptests
enable_virtual_desktop
runtests
}

werror_test() {
WINEDEBUG=""
TESTNAME="-werror"
export WINEDEBUG
export TESTNAME
preptests
runtests
}
#######################################################
##    Now to use the functions :-)
#######################################################

# Now for the script to actually do something:
# Get new tree
newtree

# Get updated winetest
get_tests_32

# Build Wine
build_regular &&

regular_test || exit 1

exit
