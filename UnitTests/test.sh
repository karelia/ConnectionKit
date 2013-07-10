#!/usr/bin/env bash

# This script builds and runs the unit tests and produces output in a format that is compatible with Jenkins.

base=`dirname $0`
echo "$base"
pushd "$base/.." > /dev/null
build="$PWD/test-build"
ocunit2junit="$base/../CurlHandle/CURLHandleSource/Tests/MockServer/UnitTests/OCUnit2JUnit/bin/ocunit2junit"
popd > /dev/null

sym="$build/sym"
obj="$build/obj"

testout="$build/output.log"
testerr="$build/error.log"

rm -rf "$build"
mkdir -p "$build"

echo Building 32-bit

xcodebuild -workspace "ConnectionKit.xcworkspace" -scheme "ConnectionKit" -sdk "macosx" -config "Debug" -arch i386 build OBJROOT="$obj" SYMROOT="$sym" > "$testout" 2> "$testerr"
if [ $? != 0 ]; then
	echo "32-bit build failed"
	cat "$testerr"
fi


echo Building and Testing 64-bit

xcodebuild -workspace "ConnectionKit.xcworkspace" -scheme "ConnectionKit" -sdk "macosx" -config "Debug" -arch x86_64 test OBJROOT="$obj" SYMROOT="$sym" > "$testout" 2> "$testerr"
if [ $? != 0 ]; then
	echo "64-bit build failed"
	cat "$testerr"
else
	cd "$build"
	"../$ocunit2junit" < "$testout"
fi


