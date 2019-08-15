L1VM README  2019-08-15
=======================
[![Codacy Badge](https://api.codacy.com/project/badge/Grade/2f0638b0ab6b433aad4d35c18d2f85c4)](https://www.codacy.com/app/koder77/l1vm?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=koder77/l1vm&amp;utm_campaign=Badge_Grade)

[![ko-fi](https://www.ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/P5P2Y3KP)

L1VM is an incredible tiny virtual machine with RISC (or comparable style) CPU, about 61 opcodes and about 36 KB binary size on X86_64 Linux (without JIT-compiler)!
The VM has a 64 bit core (256 registers for integer and double float) and can run object code
written in bracket (a high level programming language) or l1asm assembly language.

Code and data are in separated memories for a secure execution. Like in Harvard type CPUs (found now in DSPs or microcontrollers).
The opcode set with 61 opcodes is my own opinion how things should work. It does not "copy" other instruction sets known in
other "real" CPUs.

The design goals are:
<pre>
	- be small
	- be fast
	- be simple
	- be modular
</pre>
New
----
Now there is a bash script to build L1VM without JIT-compiler: "make-nojit.sh" in vm directory. You have to set "JIT_COMPILER" to "0" in the source file vm/main.c to do that. In some cases programs execute faster if they don't need the JIT-compiler to run!

I added a JIT-compiler using asmjit library. At the moment only few opcodes can be translated into code for direct execution.

L1VM ist under active development. As a proof of concept I rewrote the Nano VM fractalix SDL graphics demo in L1VM
assembly.

L1VM is 6 - 7 times faster than Nano VM, this comes from the much simpler design and dispatch speedup.

I included a few demo programs.

The source code is released under the GPL.

A simple "Hello world!" in bra(et (bracket) my language for L1VM:

<pre>
// hello.l1com
(main func)
	(set int64 1 zero 0)
	(set string 13 hello "Hello world!")
	// print string
	(6 hello 0 0 intr0)
	// print newline
	(7 0 0 0 intr0)
	(255 zero 0 0 intr0)
(funcend)
</pre>

Modules
-------
The VM modules should be installed into "/usr/local/lib".
<pre>
endianess - convert to big endian, or little endian functions
fann - FANN neural networks
file - file module
genann - neural networks module
gpio - Raspberry Pi GPIO module
math - some math functions
net - TCP/IP sockets module
process - start a new shell process
rs232 - serial port module
sdl - graphics primitves module, like pixels, lines...
string - some string functions
time - get time and date
</pre>
I will update the modules with more functions later...

NOTE
----
The current version of L1VM only runs on a Linux or other POSIX compatible OS!
If you want help to port it to a new OS, then contact me please...

TODO
----
	- make the L1COM compiler a bit more comfortable
	- write more functions for the modules
	- more demo programs

USAGE
-----

compile
-------
<pre>
$ l1com test
</pre>
compiles program "test.l1com"

assemble
--------
<pre>
$ l1asm test
</pre>
assembles program "test.l1asm" generated by the compiler

run
---
<pre>
$ l1vm test
</pre>
finally executes program "test.l1obj"

==========================================================================
