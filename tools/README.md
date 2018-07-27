# AUniter Command Line Tools

These are the command line tools for compiling Arduino sketches, uploading them
to microcontroller boards, and validating unit tests written in
[AUnit](https://github.com/bxparks/AUnit).

## Summary

The `auniter.sh` shell is a wrapper around the
[Arduino Commandline Interface](https://github.com/arduino/Arduino/blob/master/build/shared/manpage.adoc)
that allows programmatic workflows:

1) Verifying (compile) multiple `*.ino` files across multiple boards.
2) Uploading multiple `*.ino` files across multiple boards.
3) Testing multiple [AUnit](https://github.com/bxparks/AUnit) unit tests
across multiple boards.
4) Monitoring the serial monitor after uploading the sketch to a board.
5) List the tty ports and the associated Arduino boards (if available).

The script can be used with a [Jenkins](https://jenkins.io) continuous
integration system running on the local machine. Builds can be automatically
started when changes to the git repository are detected, and unit tests can be
executed on Arduino boards attached to the serial port of the local machine. The
Jenkins dashboard can display the status of builds and tests.

The `auniter.sh` script supports user-defined board aliases allow mapping of a
short alias (e.g. `nano`) to the fully qualified board name (`fqbn`) used by the
arduino binary (e.g. `arduino:avr:nano:cpu=atmega328old`).

The script can monitor the output of the serial port, and parse the output of an
AUnit unit test to determine if the test passed or failed.

## Installation

### Requirements

These scripts are meant to be used from a Linux environment. I have tested the
integration on the following systems:
    * Ubuntu 16.04
    * Ubuntu 17.10
    * Ubuntu 18.04
    * Xubuntu 18.04

The `auniter.sh` script depends on the
[Arduino IDE](https://arduino.cc/en/Main/Software) being installed
(tested with 1.8.5). I will assume that you already have this installed.

The `serial_monitor.py` script depends on
[pyserial](https://pypi.org/project/pyserial/) (tested with 3.4-1).
On Ubuntu (tested on 17.10 and 18.04), you can type:
```
$ sudo apt install python3 python3-pip python3-serial
```
to get the python3 dependencies.

### Obtain the Code

The latest development version can be installed by cloning the
[GitHub repository](https://github.com/bxparks/AUnit), and checking out the
`develop` branch. The `master` branch contains the stable release.

### Setup

There is one environment variable that **must** be defined in your `.bashrc`
file:

* `export AUNITER_ARDUINO_BINARY={path}` - location of the Arduino command line
  binary

I have something like this in my `$HOME/.bashrc` file (which I share across all
my Linux and Mac computers):
```
case $(uname -s) in
  Linux*)
    export AUNITER_ARDUINO_BINARY="$HOME/dev/arduino-1.8.5/arduino"
    ;;
  Darwin*)
    export AUNITER_ARDUINO_BINARY="$HOME/dev/Arduino.app/Contents/MacOS/Arduino"
    ;;
  *)
    export AUNITER_ARDUINO_BINARY=
    ;;
esac
```

I also recommend creating an alias for the `auniter.sh` script in your `.bashrc`
file if you use it often:
```
alias auniter='{path-to-AUniter-directory}/tools/auniter.sh'
```
(Don't add `{path-to-AUniter-directory}/tools` to your `$PATH`. It won't work
because `auniter.sh` needs to know its own install directory to find helper
scripts.)

## Usage

Type `auniter.sh --help` to get the latest usage:
```
$ ./auniter.sh --help
Usage: auniter.sh [--help] [--config file] [--verbose]
    [--verify | --upload | --test | --monitor | --list_ports]
    [--board {package}:{arch}:{board}[:parameters]] [--port port] [--baud baud]
    [--boards {alias}[:{port}],...] (file.ino | dir) [...]
```

At a minimum, the script needs to be given 3-4 pieces of information:

* mode (`--verify`, `--upload`, `--test`, `--monitor`) The mode determines the
  actions performed. Verify checks for compiler errors. Upload pushes the sketch
  to the board. Test runs the sketch as an AUnit unit test and verifies that it
  passes. Monitor uploads the sketch then echos the Serial output to the STDOUT.
* `--board board` The identifier for the particular board in the form
  of `{package}:{arch}:{board}[:parameters]`.
* `--port port` The tty port where the Arduino board can be found. This is
  optional for the `--verify` mode which does not need to connect to the board.
* `file.ino` The Arduino sketch file.

### Verify (--verify)

The following example verifies that the `Blink.ino` sketch compiles. The
`--port` flag is not necessary in this case:

```
$ ./auniter.sh --verify \
  --board arduino:avr:nano:cpu=atmega328old Blink.ino
```

### Upload (--upload)

To upload the sketch to the Arduino board, we need to provide the
`--port` flag:

```
$ ./auniter.sh --upload --port /dev/ttyUSB0 \
  --board arduino:avr:nano:cpu=atmega328old Blink.ino
```

### Test (--test)

To run the AUnit test and verify pass or fail:
```
$ ./auniter.sh --test --port /dev/ttyUSB0 \
  --board arduino:avr:nano:cpu=atmega328old tests/*Test
```

A summary of all the test runs are given at the end, like this:

```
[...]
======== Test Run Summary
PASSED test: arduino:avr:nano:cpu=atmega328old /dev/ttyUSB1 AceSegment/tests/CommonTest/CommonTest.ino
PASSED test: arduino:avr:nano:cpu=atmega328old /dev/ttyUSB1 AceSegment/tests/DriverTest/DriverTest.ino
PASSED test: arduino:avr:nano:cpu=atmega328old /dev/ttyUSB1 AceSegment/tests/LedMatrixTest/LedMatrixTest.ino
PASSED test: arduino:avr:nano:cpu=atmega328old /dev/ttyUSB1 AceSegment/tests/RendererTest/RendererTest.ino
PASSED test: arduino:avr:nano:cpu=atmega328old /dev/ttyUSB1 AceSegment/tests/WriterTest/WriterTest.ino
ALL PASSED
```

The `ALL PASSED` indicates that all unit tests passed.

### Monitor (--monitor)

The `--monitor` mode uploads the given sketch and calls `serial_monitor.py`
to listen to the serial monitor and echo the output to the STDOUT:
```
$ ./auniter.sh --monitor --port /dev/ttyUSB0 \
  --board arduino:avr:nano:cpu=atmega328old BlinkTest.ino
```

The `serial_monitor.py` times out after 10 seconds if the serial monitor is
inactive. If the sketch continues to output something to the serial monitor,
then only one sketch can be monitored.

### List Ports (--list_ports)

The `--list_ports` flag will ask `serial_monitor.py` to list the available tty
ports:
```
$ ./auniter.sh --list_ports
/dev/ttyS4 - n/a
/dev/ttyS0 - ttyS0
/dev/ttyUSB2 - CP2102 USB to UART Bridge Controller
/dev/ttyUSB1 - EzSBC ESP32
/dev/ttyUSB0 - USB2.0-Serial
/dev/ttyACM1 - USB Serial
/dev/ttyACM0 - Arduino Leonardo
```

### Automatic Directory Expansion

If the `auniter.sh` is given a directory `dir`, it tries to find
an ino file located at `dir/dir.ino`, since the ino file must have the
same base name as the parent directory.

Multiple files and directories can be given. The Arduino Commandline will
be executed on each of the ino files in sequence.

### Board Aliases

The Arduino command line binary wants a fully-qualified board name (`fqbn`)
specification for the `--board` flag. It can be quite cumbersome to determine
this value. One way is to set the "Show verbose output during compilation and
upload" checkboxes in the Arduino IDE, then look for the value of the `-fqbn`
flag generated in the debug output. Another way is to track down the
`hardware/.../boards.txt` file (there may be several verisons), open it up, and
try to reverse engineer the `fqbn` of a particular Arduino board.

On some boards, the `fqbn` may be quite long. For example, on my ESP32 dev
board, it is
```
espressif:esp32:esp32:PartitionScheme=default,FlashMode=qio,FlashFreq=80,FlashSize=4M,UploadSpeed=921600,DebugLevel=none
```

It is likely that not all the extra parameters are needed, but it is not
easy to figure out which ones can be left out.

Instead of using the `fqbn`, the `auniter.sh` script allows the user to define
aliases for the `fqbn` in a file. The format of the file is the
[INI file](https://en.wikipedia.org/wiki/INI_file), and the aliases are
in the `[boards]` section:
```
# Board aliases
[boards]
  uno = arduino:avr:uno
  nano = arduino:avr:nano:cpu=atmega328old
  leonardo = arduino:avr:leonardo
  esp8266 = esp8266:esp8266:nodemcuv2:CpuFrequency=80,FlashSize=4M1M,LwIPVariant=v2mss536,Debug=Disabled,DebugLevel=None____,FlashErase=none,UploadSpeed=115200
  esp32 = espressif:esp32:esp32:PartitionScheme=default,FlashMode=qio,FlashFreq=80,FlashSize=4M,UploadSpeed=921600,DebugLevel=none
```

The format of the alias name is not precisely defined, but it should probably be
limited to the usual character set for identifiers (`a-z`, `A-Z`, `0-9`,
underscore `_`). It definitely cannot contain an equal sign `=` or space
character.

The board aliases can be saved into the AUniter config file. They can be
referenced using the `--boards` flag.

### Config File (--config)

By default, the `auniter.sh` script looks in the
```
$HOME/.auniter.conf
```
file in your home directory. The script can be told to look elsewhere using the
`--config` command line flag. (Use `--config /dev/null` to indicate no config
file.) This may be useful if the config file is checked into source control for
each Arduino project.

### Multiple Boards (--boards)

The board aliases can be used in the `--boards` flag, which accepts a
comma-separated list of `{alias}[:{port}]` pairs.

The `port` part of the `alias:port` pair is optional because it is not needed
for the `--verify` mode. You can verify sketches across multiple boards like
this:

```
$ ./auniter.sh --verify \
  --boards nano,leonardo,esp8266,esp32 BlinkTest.ino
```

If you want to run the AUnit tests on multiple boards, you must provide the
port of each board, like this:
```
$ ./auniter.sh --test \
  --boards nano:/dev/ttyUSB0,leonardo:/dev/ttyACM0,esp8266:/dev/ttyUSB2,esp32:/dev/ttyUSB1 \
  CommonTest DriverTest LedMatrixTest RendererTest WriterTest
```

This runs the 5 unit tests on 4 boards connected to the ports specified by the
`--boards` flag.

It did not seem worth providing aliases for the ports in the
`$HOME/.auniter.conf` file because the specific serial port is assigned by the
OS and can vary depending on the presence of other USB or serial devices.

### Mutually Exclusive Access

Multiple instances of the `auniter.sh` script can be executed, which can help
with the `--verify` operation if you have multiple CPU cores. However, when the
`--upload` or `--test` mode is selected, it is important to ensure that only one
instance of the Arduino IDE uploads and/or monitors the serial port at given
time. Otherwise one instance of the `auniter.sh` script can accidentally
see the output of another `auniter.sh` and cause confusion.

The `auniter.sh` script uses a locking mechanism on the serial port of the
Arduino board (using the [flock(1)](https://linux.die.net/man/1/flock) command)
to prevent multiple uploads to and monitoring of the same Arduino board
at the same time. Unfortunately, the locking does not work for the Pro Micro or
Leonardo boards (using ATmega32U4) which use virtual serial ports.

By default, the locking is performed. There are 2 ways to disable the locking:

1) Use the `--[no]locking` flag on the `auniter.sh` script.

2) Add an entry for a specific board alias under the `[options]` section in the
  `CONFIG_FILE`. The format looking like this:
```
[boards]
  leonardo = arduino:avr:leonardo

[options]
  leonardo = --nolocking
```

If the flag is given in both places, then the the command line flag takes
precedence over the `CONFIG_FILE` to allow overriding of the value in the config
file.

## Integration with Jenkins

I have successfully integrated `auniter.sh` into a locally hosted
[Jenkins](https://jenkins.io) Continuous Integration platform. The details are
given in the [Continuous Integration with Jenkins](jenkins) page.

## Alternatives Considered

### AMake

The [amake](https://github.com/pavelmc/amake) tool is very similar to
`auniter.sh`. It is a shell script that calls out to the Arduino commandline.
Amake does not have the `serial_monitor.py` which allows the AUnit output on the
serial port to be validated, but since `serial_monitor.py` is a separate
Python script, `amake` could be extended to support it.

There are a few features of `amake` that I found problemmatic for my purposes.
* Although `amake` supports the concept of board aliases, the aliases are
hardwared into the `amake` script itself. I felt that it was important to allow
users to define their own board aliases (through the `.auniter.conf` dotfile).
* `amake` saves the information about the most recent `*.ino` file and
board type in a cache file named `.amake` in the current directory. This was
designed to make it easy to compile and verify a single INO file repeatedly.
However, `auniter.sh` is designed to make it easy to compile, upload, and
validate multiple INI files, on multiple Arduino boards, on multiple serial
ports.

### Arduino-Makefile

The [Arduino-Makefile](https://github.com/sudar/Arduino-Makefile) package
provides a way to create traditional Makefiles and use the traditional `make`
command line program to compile an Arduino sketch. On Ubuntu Linux,
this package can be installed using the normal `apt` program as:
```
$ sudo apt install arduino-mk
```

It installs a dependency called
[arduino-core](https://packages.ubuntu.com/search?keywords=arduino-core).
Unfortunately, the version on Ubuntu is stuck at Arduino version 1.0.5
and the process for upgrading been
[stuck for years](https://github.com/arduino/Arduino/pull/2703).

It is possible to configure Arduino-Makefile to use the latest Arduino IDE
however.

The problem with `Arduino-Makefile` is that it seems to allow only a single
board type target in the Makefile. Changing the target board would mean editting
the `Makefile`. Since I wanted to be able to easily compile, upload and validate
against multiple boards, the `Makefile` solution did not seem to be flexible
enough.

### PlatformIO

[PlatformIO](https://platformio.org) is a comprehensive platform for
IoT development. It is split into several components. The
[PlatformIO IDE](http://docs.platformio.org/en/latest/ide/pioide.html)
is based on the [Atom](https://atom.io) editor. The
[PlatformIO Core](http://docs.platformio.org/en/latest/core.html)
is a set of command line tools (written in Python mostly) that build, compile,
and upload the code.

A given Arduino project is defined by the `platformio.ini` file, which is the
equilvalent to the `Makefile`. Unlike `Arduino-Makefile`, multiple embedded
boards (e.g. Nano, ESP8266, ESP32) can be defined in a single `platformio.ini`
file. Like a `Makefile`, the `platformio.ini` file allows finer-grained control
of the various build options, as well as better control over the dependencies.

I currently have only limited experience with PlatformIO, but I think it would
be feasible to integrate PlatformIO tools into a locally running Jenkins service
like I did with `auniter.sh`. However, I think it has some disadvantages. It is
a far more complex than the Arduino IDE, so the learning curve is longer. Also,
it seems that the `platformio.ini` file must be created for every unit of
compilation and upload, in other words, for every `*.ino` file. This seems to be
too much overhead when a project has numerous AUnit unit test files, each of
them being a separate `*.ino` file.

The `platformio.ini` files provide better isolation between `*.ino` files, but
the overhead seem too much for me and I think most people. I may revisit
PlatformIO at a later time.

### Arduino Builder

The [Arduino Builde](https://github.com/arduino/arduino-builder) seems to be a
collection of Go-lang programs that provide commandline interface for compiling
Arduino sketches. However, I have not been able to find any documentation that
describes how to actually to use these programs. Maybe eventually I'll be able
to reverse-engineer it, but for now, it was easier for me to write my down shell
script wrapper around the Arduino IDE program.

## System Requirements

I used Arduino IDE 1.8.5 for all my testing, and the `AUniter` scripts
have been verified to work under:

* Ubuntu 16.04
* Ubuntu 17.10
* Ubuntu 18.04
* Xubuntu 18.04

Some limited testing on MacOS has been done, but it is currently not supported.

Windows is definitely not supported because the scripts require the `bash`
shell. I am not familiar with
[Windows Subsystem for Linux](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
so I do not know if it would work on that.

## Limitations

[Teensyduino](https://pjrc.com/teensy/teensyduino.html) is not
currently supported because of Issue #4.

On MacOS, the [Teensyduino](https://pjrc.com/teensy/teensyduino.html)
plugin to support Teensy boards causes the Arduino IDE to display
[a security warning dialog box](https://forum.pjrc.com/threads/27197-OSX-pop-up-when-starting-Arduino).
This means that the script is no longer able to run without human-intervention.
