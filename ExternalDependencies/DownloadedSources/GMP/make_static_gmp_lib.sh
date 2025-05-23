#!/bin/bash

GMP_VERSION="6.2.1"
PLATFORMPATH="/Applications/Xcode.app/Contents/Developer/Platforms"
TOOLSPATH="/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
export IPHONEOS_DEPLOYMENT_TARGET="13.0"
pwd=`pwd`

findLatestSDKVersion()
{
    sdks=`ls $PLATFORMPATH/$1.platform/Developer/SDKs`
    arr=()
    for sdk in $sdks
    do
       arr[${#arr[@]}]=$sdk
    done

    # Last item will be the current SDK, since it is alpha ordered
    count=${#arr[@]}
    if [ $count -gt 0 ]; then
       sdk=${arr[$count-1]:${#1}}
       num=`expr ${#sdk}-4`
       SDKVERSION=${sdk:0:$num}
    else
       SDKVERSION="8.0"
    fi
}

buildit()
{
    target=$1
    hosttarget=$1
    platform=$2

    if [[ $hosttarget == "x86_64" ]]; then
        hostarget="i386"
    elif [[ $hosttarget == "arm64" ]]; then
        hosttarget="arm"
	if [[ $platform == "iPhoneSimulator" ]]; then
	    target_simulator="-target arm64-apple-ios13.0-simulator"
	else
	    target_simulator=""
	fi
    fi


    export CC="$(xcrun -sdk iphoneos -find clang)"
    export CPP="$CC -E"
    export CFLAGS="-arch ${target} ${target_simulator} -isysroot $PLATFORMPATH/$platform.platform/Developer/SDKs/$platform$SDKVERSION.sdk --sysroot $PLATFORMPATH/$platform.platform/Developer/SDKs/$platform$SDKVERSION.sdk -miphoneos-version-min=$IPHONEOS_DEPLOYMENT_TARGET -flto"
    export AR=$(xcrun -sdk iphoneos -find ar)
    export RANLIB=$(xcrun -sdk iphoneos -find ranlib)
    export CPPFLAGS="-arch ${target} ${target_simulator} -isysroot $PLATFORMPATH/$platform.platform/Developer/SDKs/$platform$SDKVERSION.sdk --sysroot $PLATFORMPATH/$platform.platform/Developer/SDKs/$platform$SDKVERSION.sdk -miphoneos-version-min=$IPHONEOS_DEPLOYMENT_TARGET"
    export LDFLAGS="-arch ${target} -isysroot $PLATFORMPATH/$platform.platform/Developer/SDKs/$platform$SDKVERSION.sdk --sysroot $PLATFORMPATH/$platform.platform/Developer/SDKs/$platform$SDKVERSION.sdk"
    export CC_FOR_BUILD="IPHONEOS_DEPLOYMENT_TARGET='' clang"

    if [ -d $pwd/builds/gmp-$GMP_VERSION/$platform/$target ]; then
	echo "A build already exists for GMP v$GMP_VERSION for platform $platform and target $target."
    else
	echo "Starting the build for GMP v$GMP_VERSION for target $target."
	echo -e "\thosttarget = $hosttarget"
	echo -e "\tCC         = $CC"
	echo -e "\tCPP        = $CPP"
	echo -e "\tCFLAGS     = $CFLAGS"
	echo -e "\tAR         = $AR"
	echo -e "\tRANLIB     = $RANLIB"
	echo -e "\tCPPFLAGS   = $CPPFLAGS"
	echo -e "\tLDFLAGS    = $LDFLAGS"
	echo -e "\tCC         = $CC"

	mkdir -p $pwd/builds/gmp-$GMP_VERSION/$platform/$target

	./configure --prefix="$pwd/builds/gmp-$GMP_VERSION/$platform/$target" --disable-shared --enable-static --host=$hosttarget-apple-darwin --disable-assembly

	make clean
	make
	make install
    fi
}

distclean()
{
    cd $pwd/tmp/gmp-$GMP_VERSION
    if [ -f Makefile ]; then
	make distclean
    fi
}

# Step 0: Find the latest SDK version

findLatestSDKVersion iPhoneOS
echo "Latest SDK version:" $SDKVERSION
echo "iOS deployment target:" $IPHONEOS_DEPLOYMENT_TARGET

# Step 1: Uncompress the GMP source in ./tmp

echo "Uncompressing GMP v$GMP_VERSION..."
mkdir -p $pwd/tmp
cp $pwd/gmp_releases/gmp-$GMP_VERSION.tar.lz $pwd/tmp/
cd $pwd/tmp/
tar xf gmp-$GMP_VERSION.tar.lz


# Step 2: Distclean if possible

distclean

# Step 3: Build

buildit arm64 iPhoneSimulator
distclean
buildit x86_64 iPhoneSimulator
distclean
buildit arm64 iPhoneOS
distclean

# Step 4: Lipo the libraries for the various architectures for the simulator into one static library.

echo "Building universal static library for the simulator..."
platform="iPhoneSimulator"
LIPO=$(xcrun -sdk iphoneos -find lipo)
mkdir -p $pwd/builds/gmp-$GMP_VERSION/$platform/universal
$LIPO -create $pwd/builds/gmp-$GMP_VERSION/$platform/arm64/lib/libgmp.a $pwd/builds/gmp-$GMP_VERSION/$platform/x86_64/lib/libgmp.a -output $pwd/builds/gmp-$GMP_VERSION/$platform/universal/libgmp.a
cp $pwd/builds/gmp-$GMP_VERSION/$platform/arm64/include/gmp.h $pwd/builds/gmp-$GMP_VERSION/$platform/universal/

# No need to create a universal lib for the iPhone since there is only one architecture
