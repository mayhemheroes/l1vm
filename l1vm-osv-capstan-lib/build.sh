#!/bin/sh
echo "capstan must be installed to run this script..."
echo "L1VM must be configured without SDL support to build OSv l1vm!"
echo "copy buildfile"
cp zerobuild-osv.txt ../vm
cd ../vm
echo "building l1vm-osv.so"
zerobuild zerobuild-osv.txt force
cp l1vm-osv.so ../l1vm-osv-capstan-lib
cd ../lib
cp string.l1obj ../l1vm-osv-capstan-lib
cd ../l1vm-osv-capstan-lib
cp ../vm/modules/string/libl1vmstring.so .
capstan package pull osv.bootstrap
capstan package compose l1vm
echo "running OSv image using qemu..."
capstan run l1vm
