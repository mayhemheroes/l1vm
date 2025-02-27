#!/bin/bash
# install includes

mkdir ~/l1vm
mkdir ~/l1vm/include
cp include-lib/* ~/l1vm/include/

for i in prog/*.l1asm
do
	filename=$(basename "$i" .l1asm)
	l1asm prog/$filename
done
	
for i in prog/*.l1com
do
	filename=$(basename "$i" .l1com)
	./l1vm-build.sh prog/$filename -sizes 1000000 1000000000
done
rm prog/*.l1asm.l1dbg
exit 0
