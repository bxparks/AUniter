# AUniter Command Line Tools

These are the command line tools for compiling Arduino sketches, uploading them
to microcontroller boards, and validating unit tests written in
[AUnit](https://github.com/bxparks/AUnit).

## Summary

The `auniter.sh` shell is a wrapper around the
[Arduino Commandline Interface](https://github.com/arduino/Arduino/blob/master/build/shared/manpage.adoc)
that supports the following functionality:

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
short alias (e.g. `uno`) to the fully qualified board name (`fqbn`) used by the
arduino binary (e.g. `arduino:avr:uno`).

The script can monitor the output of the serial port, and parse the output of an
AUnit unit test to determine if the test passed or failed.

## Installation

### Requirements

These scripts are meant to be used from a Linux environment. The following
components and version numbers have been tested:

* Ubuntu Linux
    * Ubuntu 16.04
    * Ubuntu 17.10
    * Ubuntu 18.04
    * Xubuntu 18.04
* [Arduino IDE](https://arduino.cc/en/Main/Software):
    * 1.8.5
    * 1.8.6
* [pyserial](https://pypi.org/project/pyserial/)
    * 3.4-1
    * install: `sudo apt install python3 python3-pip python3-serial`
* [picocom](https://linux.die.net/man/8/picocom)
    * (optional, for `auniter.sh monitor` functionality)
    * 2.2
    * install: `sudo apt install picocom`

Some limited testing on MacOS has been done, but it is currently not supported.

Windows is definitely not supported because the scripts require the `bash`
shell. I am not familiar with
[Windows Subsystem for Linux](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
so I do not know if it would work on that.

### Obtain the Code

The latest development version can be installed by cloning the
[GitHub repository](https://github.com/bxparks/AUniter), and checking out the
`develop` branch. The `master` branch contains the stable release. The
`auniter.sh` script is in the `./tools` directory.

### Environment Variable

There is one environment variable that **must** be defined in your `.bashrc`
file:

* `export AUNITER_ARDUINO_BINARY={path}` - location of the Arduino command line
  binary

I have something like this in my `$HOME/.bashrc` file:
```
export AUNITER_ARDUINO_BINARY="$HOME/dev/arduino-1.8.5/arduino"
```

### Shell Alias

I recommend creating an alias for the `auniter.sh` script in your `.bashrc`
file:
```
alias auniter='{path-to-AUniter-directory}/tools/auniter.sh'
```
Don't add `{path-to-AUniter-directory}/tools` to your `$PATH`. It won't work
because `auniter.sh` needs to know its own install directory to find helper
scripts.

**(The rest of the document will assume that you have created this alias.)**

### Config File

The `auniter.sh` script looks for a config file named `$HOME/.auniter.conf` in
your home directory. The format of the file is the
[INI file](https://en.wikipedia.org/wiki/INI_file),
and the meaning of these properties will be explained below. For the purposes of
this tutorial, create an initial `.auniter.conf` file with the following
content:
```
# Tool settings
[auniter]
  monitor = picocom -b $baud --omap crlf --imap lfcrlf --echo $port
# Board aliases
[boards]
  uno = arduino:avr:uno
```

The examples below will make use of this initial setting.

## Usage

Type `auniter --help` to get the latest usage. Here is the summary portion
of the help message:
```
$ auniter --help
Usage: auniter.sh [auniter_flags] command [command_flags] [boards] [files...]
       auniter.sh ports
       auniter.sh verify {board},... files ...
       auniter.sh upload {board}:{port},... files ...
       auniter.sh test {board}:{port},... files ...
       auniter.sh monitor [{board}:]{port}
       auniter.sh upmon {board}:{port}
```

The 6 subcommands (`ports`, `verify`, `upload`, `test`, `monitor`, `upmon`) are
described below.

### Board Aliases {board}

The Arduino IDE binary wants a fully-qualified board name (`fqbn`)
specification for the `--board` flag. It can be quite cumbersome to determine
this value. The easiest way is to set the "Show verbose output during
compilation and upload" checkboxes in the Arduino IDE, then look for the value
of the `-fqbn` flag generated in the debug output. Another way is to track down
the `hardware/.../boards.txt` file (there may be several verisons), open it up,
and try to reverse engineer the `fqbn` of a particular Arduino board.

On some boards, the `fqbn` may be quite long. For example, on my ESP32 dev
board, it is
```
espressif:esp32:esp32:PartitionScheme=default,FlashMode=qio,FlashFreq=80,FlashSize=4M,UploadSpeed=921600,DebugLevel=none
```

Instead of using the `fqbn`, the `auniter.sh` script uses board
aliases for the `fqbn` the `.auniter.conf` file, in the `[boards]` section.
My config file looks something like this:
```
# Board aliases
[boards]
  uno = arduino:avr:uno
  nano = arduino:avr:nano:cpu=atmega328old
  leonardo = arduino:avr:leonardo
  esp8266 = esp8266:esp8266:nodemcuv2:CpuFrequency=80,FlashSize=4M1M,LwIPVariant=v2mss536,Debug=Disabled,DebugLevel=None____,FlashErase=none,UploadSpeed=115200
  esp32 = espressif:esp32:esp32:PartitionScheme=default,FlashMode=qio,FlashFreq=80,FlashSize=4M,UploadSpeed=921600,DebugLevel=none
```

(The allowed characters in the board alias name is not precisely defined, but it
should probably be limited to the usual character set for identifiers (`a-z`,
`A-Z`, `0-9`, underscore `_`). It definitely cannot contain an equal sign `=` or
space character.)

### Port Specifier {port}

Some subcommands (`upload`, `test`, `monitor`) also needs to be given the serial port that the Arduino board is
connected to. The serial port on a Linux machine has the form `/dev/ttyXXXn`,
for example `/dev/ttyUSB0`. For convenience, the repetitive `/dev/tty` part can
be omitted from the `{port}` spec. In other words, you can write `uno:USB0`,
instead of `uno:/dev/ttyUSB0`.

### Multiple Boards and Ports

Some commands (`upload`, `test`) accept multiple boards and ports
using `{board}:{port}` pairs separated by commas (without spaces).
For example:
```
nano:USB0,leonardo:ACM0:esp8266:USB1,esp32:USB2
```

### Subcommand: Ports

The `ports` command simply lists the available serial ports:
```
$ auniter ports
/dev/ttyS4 - n/a
/dev/ttyS0 - ttyS0
/dev/ttyUSB2 - CP2102 USB to UART Bridge Controller
/dev/ttyUSB1 - EzSBC ESP32
/dev/ttyUSB0 - USB2.0-Serial
/dev/ttyACM1 - USB Serial
/dev/ttyACM0 - Arduino Leonardo
```

### Subcommand: Verify

The following examples (all equivalent) verify that the `Blink.ino` sketch
compiles. The `{port}` of the board is not necessary because the program
is not uploaded to the board:

```
$ auniter verify uno Blink.ino
```

### Subcommand: Upload

To upload the sketch to the Arduino board, we need to provide the port
of the board. The following examples are equivalent:

```
$ auniter upload uno:USB0 Blink.ino
$ auniter upload uno:/dev/ttyUSB0 Blink.ino
```

### Subcommand: Test

The `auniter test` command compiles the program, uploads it to the specified
board, then reads the serial output from the boards, looking for specific
output from the [AUnit](https://github.com/bxparks/AUnit) test runner.
```
$ auniter test uno:USB0 BlinkTest.ino
```

A summary of all the test runs are given at the end, like this:

```
[...]
======== Test Run Summary
PASSED test: arduino:avr:uno /dev/ttyUSB0 AceSegment/tests/CommonTest/CommonTest.ino
PASSED test: arduino:avr:uno /dev/ttyUSB0 AceSegment/tests/DriverTest/DriverTest.ino
PASSED test: arduino:avr:uno /dev/ttyUSB0 AceSegment/tests/LedMatrixTest/LedMatrixTest.ino
PASSED test: arduino:avr:uno /dev/ttyUSB0 AceSegment/tests/RendererTest/RendererTest.ino
PASSED test: arduino:avr:uno /dev/ttyUSB0 AceSegment/tests/WriterTest/WriterTest.ino
ALL PASSED
```

The `ALL PASSED` indicates that all unit tests passed.

### Subcommand: Monitor

The serial port of the board can be monitored using the `monitor` subcommand. It
needs to know the tty serial port which can be given in any of the following
equivalent ways:
```
$ auniter monitor USB0
$ auniter monitor uno:USB0
$ auniter monitor /dev/ttyUSB0
```

When the port is given as `{board}:{port}`, the `{board}` part is ignored. This
feature is useful in interactive mode, so that you can scroll through the shell
history and simply change the `auniter upload ...` to `auniter monitor ...`
without having to also remove the `{board}:` part.

The speed of the serial port is usually controlled by the program that is
running on the Arduino board (through the `Serial.begin(xxxx)` statement.
The port speed value can be given by the `--baud` flag. The default is 115200,
but you can change it like this:
```
$ auniter monitor --baud 9600 USB0
```

The `monitor` subcommand delegates the serial terminal functionality to a
user-defined program defined in the `auniter.conf` file. The program that works
well for me is the [picocom](https://linux.die.net/man/8/picocom) program. On
Ubuntu Linux, install it using:
```
$ sudo apt install picocom
```

With the following definition in the `.auniter.conf` file:
```
[auniter]
  monitor = picocom -b $baud --omap crlf --imap lfcrlf --echo $port
```

the `auniter.sh` script will fill in the `$baud` and `$port` and execute this
command. (Note: The exit command for `picocom` is `Ctrl-a Ctrl-q` but if you are
in a terminal multiplexer like `screen`, then `Ctrl-a` is the escape character
for `screen` itself, you have to type `Ctrl-a a Ctrl-q` instead.)

### Subcommand: Upload and Monitor (upmon)

Often we want to upload a program then immediately monitor the serial port, to
view the serial port output, or to send commands to the board over the serial
port. You can do that using the `upmon` command:
```
$ auniter upmon uno:USB0 Blink.ino
```

The argument list is very similar to `upload` except that `upmon` accepts
only a single `{board}:{port}` pair.

## Advanced Usage

The following features are useful if you are working with multiple board types,
and/or if you are using `auniter.sh` as the driving script for the
[Jenkins continuous integration](../jenkins).

### Automatic Directory Expansion

If the `auniter.sh` is given a directory `dir`, it tries to find
an ino file located at `dir/dir.ino`, since the ino file must have the
same base name as the parent directory.

Multiple files and directories can be given. The Arduino Commandline will
be executed on each of the ino files in sequence.

### Multiple Boards

The `verify`, `upload` and `test` commands all support multiple board/port pairs
by listing them as a comma-separated list of `{board}:{port}`. For example, we
can compile (verify) a single sketch across multiple boards like this:

```
$ auniter verify uno,leonardo,esp8266,esp32 BlinkTest.ino
```

If you want to run the AUnit tests on multiple boards, you must provide the
port of each board, like this:
```
$ auniter test uno:USB0,leonardo:ACM0,esp8266:USB2,esp32:USB1 \
  CommonTest DriverTest LedMatrixTest RendererTest WriterTest
```

There are no provision for creating aliases for the ports in the
`$HOME/.auniter.conf` file because the serial port is assigned by the OS and can
vary depending on the presence of other USB or serial devices.

### Mutually Exclusive Access (--locking, --nolocking)

(Valid for subcomands: `upload`, `test`)

Multiple instances of the `auniter.sh` script can be executed, which can help
with the `verify` subcommand if you have multiple CPU cores. However, when the
`upload` or `test` subcommand is selected, it is important to ensure that only
one instance of the Arduino IDE uploads and/or monitors the serial port at given
time. Otherwise one instance of the `auniter.sh` script can accidentally
see the output of another `auniter.sh` and cause confusion.

The `auniter.sh` script uses a locking mechanism on the serial port of the
Arduino board (using the [flock(1)](https://linux.die.net/man/1/flock) command)
to prevent multiple uploads to and monitoring of the same Arduino board
at the same time. Unfortunately, the locking does not work for the Pro Micro or
Leonardo boards (using ATmega32U4) which use virtual serial ports.

By default, the locking is performed. There are 2 ways to disable the locking:

1) Use the `--[no]locking` flag on the `auniter.sh` script.
```
$ auniter test --nolocking leonardo:USB0 tests/*Test
```

2) Add an entry for a specific board alias under the `[options]` section in the
  `CONFIG_FILE`. The format looks like this:
```
[boards]
  leonardo = arduino:avr:leonardo

[options]
  leonardo = --nolocking
```

If the flag is given in both places, then the the command line flag takes
precedence over the `CONFIG_FILE` to allow overriding of the value in the config
file.

### Excluding Files (--exclude regexp)

(Valid for subcomands: `verify`, `upload`, `test`)

Some programs cannot be compiled under some microcontroller boards.
The `--exclude regexp` option will skip any `*.ino` files whose fullpath
matches the regular expression used by
[egrep](https://linux.die.net/man/1/egrep).

This flag is intended to be used in the `[options]` section of the
`CONFIG_FILE` for a given board target, like this:
```
[boards]
  esp8266 = ...
  esp32 = ...

[options]
  esp8266 = --exclude AceButton/examples/CapacitiveButton
  esp32 = --exclude AceButton/examples/CapacitiveButton
```

The `CapacitiveButton` program does not compile for ESP8266 or ESP32 boards.
This entry in the `CONFIG_FILE` will cause `auniter.sh` to skip this file for
all modes (verify, upload, test, monitor).

Multiple files can be specified using the `a|b` regular expression:
```
  esp8266 = --exclude AceButton/examples/CapacitiveButton|AceButton/examples/StopWatch
```

If the flag is given to the `auniter.sh` script explicitly, it will override
the value in `CONFIG_FILE`. Therefore, you can explicitly compile a program
that is excluded from the `CONFIG_FILE` by giving a regexp which matches
nothing. For example:
```
$ auniter verify --exclude none esp8266 CapacitiveButton
```

### Alternative Ways to Specify the Board and Port

### Config File (--config)

(Valid on the `auniter.sh` command)

By default, the `auniter.sh` script looks in the
```
$HOME/.auniter.conf
```
file in your home directory. The script can be told to look elsewhere using the
`--config` command line flag. (Use `--config /dev/null` to indicate no config
file.) This may be useful if the config file is checked into source control for
each Arduino project.

```
$ auniter --config {path-to-config-file} subcommand {board:port} ...
```

(The `--config` flag is an option on the `auniter.sh` command, not the
subcommand, so it must occur *before* the subcommands.)

### Verbose Mode (--verbose)

(Valid on the `auniter.sh` command)

The `auniter.sh` accepts a `--verbose` flag, which enables verbose mode for
those subcommands which support it. In particular, it is passed into the Arduino
binary, which then prints out the compilation steps in extreme detail.

### Default Baud Rate

If the `--baud` flag is not given, then default baud rate for the serial port is
set to `115200`. You can change this default value in the `.auniter.conf` file
using the `baud` property in the `[auniter]` section. For example, the following
sets the default baud rate to 9600 in the absence of an explicit `--baud` flag:
```
[auniter]
  baud = 9600
```

## Integration with Jenkins

I have successfully integrated `auniter.sh` into a locally hosted
[Jenkins](https://jenkins.io) Continuous Integration platform. The details are
given in the [Continuous Integration with Jenkins](../jenkins) page.

## Alternatives Considered

### AMake

The [amake](https://github.com/pavelmc/amake) tool is very similar to
`auniter.sh`. It is a shell script that calls out to the Arduino commandline.

There are a few features of `amake` that I found problemmatic for my purposes.
* Although `amake` supports the concept of board aliases, the aliases are
hardwared into the `amake` script itself. I felt that it was important to allow
users to define their own board aliases (through the `.auniter.conf` dotfile).
* `amake` saves the information about the most recent `*.ino` file and
board type in a cache file named `.amake` in the current directory. This was
designed to make it easy to compile and verify a single INO file repeatedly.
However, `auniter.sh` is designed to make it easy to compile, upload, and
validate multiple `*.ino` files, on multiple Arduino boards, on multiple serial
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

## Tips

### Verify All Programs Under Current Directory

When I write libraries, I tend create a lot of small sketches for various
purposes (e.g. demos, examples, unit tests). For example, here's the directory
structure for my [AceButton](https://github.com/bxparks/AceButton) library:
```
AceButton/
|-- docs
|   `-- html
|-- examples
|   |-- AutoBenchmark
|   |-- CapacitiveButton
|   |-- ClickVersusDoubleClickUsingBoth
|   |-- ClickVersusDoubleClickUsingReleased
|   |-- ClickVersusDoubleClickUsingSuppression
|   |-- HelloButton
|   |-- SingleButton
|   |-- SingleButtonPullDown
|   |-- Stopwatch
|   `-- TunerButtons
|-- src
|   `-- ace_button
`-- tests
    `-- AceButtonTest
```

There are 11 `*.ino` program files under `AceButton/`. Here is a one-liner
that will compile and verify all 11 sketches in one shot:
```
$ cd AceButton
$ auniter verify uno $(find -name '*.ino')
```

## Limitations

[Teensyduino](https://pjrc.com/teensy/teensyduino.html) is not
currently supported because of Issue #4.
