# ping-arduino-loader
Detect an arduino loader attached to a serial port.

The single command-line parameter is the port name.

The rationale for development was that the author had an "upcycled" ATMEGA649V
board, onto which he'd written the ButterflyCore loader. However this wasn't
responding since (a) the resonator speed couldn't be read and (b) the sense of
the reset signal wasn't as expected.

The program was written using Free Pascal and the Lazarus IDE, it has no external
dependencies. It's been tested on x86_64 Linux, but should be portable.
