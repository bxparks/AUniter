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
short alias (e.g. `nano`) to the fully qualified board name (`fqbn`) used by the
arduino binary (e.g. `arduino:avr:nano:cpu=atmega328old`).

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

## Usage

Type `auniter --help` to get the latest usage:
```
$ auniter --help
Usage: auniter.sh [auniter_flags] command [command_flags] [boards] [files...]
    auniter.sh ports
    auniter.sh verify {board} files ...
    auniter.sh upload {board:port} files ...
    auniter.sh test {board:port} files ...
    auniter.sh monitor ({port} | {board:port})
```

The 5 subcommands (ports, verify, upload, test, monitor) are described below.
Three of the commands need the board and port of the target controller. There
are 3 ways to specify these:

* explicit flags
    * `--board board` The identifier for the particular board in the form
      of `{package}:{arch}:{board}[:parameters]`.
    * `--port port` The tty port where the Arduino board can be found. This is
      optional for the `verify` subcommand which does not need to connect to the
      board.
    * These flags are passed directly to the Arduino IDE.
* --boards {alias:port}
    * The `alias` is searched in the `auniter.conf` file and if found,
      the actual value of the `--board` flag is passed to the Arduino IDE.
    * The `port` is passed to the `--port` flag. For convenience, the
      repetitive `/dev/tty` part can be omitted from the `{port}` spec. In other
      words, you can write `nano:USB0`, instead of `nano:/dev/ttyUSB0`.
* {alias:port}
    * If the `--board` or `--boards` flags are not given, then the `verify`,
      `upload`, and `test` commands expect the next (non-flag) argument to be
      the `{alias:port}` parameter of the `--boards` flag, so that explicit flag
      can be dropped. The examples below will hopefully make these more clear.

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
aliases for the `fqbn` in a config file. The format of the file is the
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

The board alias can be used with the `--boards` flag (not to be confused with
the `--board` flag which is passed directly to the Arduino binary). The
`--boards` flag is described below.

### Config File (--config)

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
compiles. The `--port` flag is not necessary in this case:

```
$ auniter verify --board arduino:avr:nano:cpu=atmega328old Blink.ino
$ auniter verify --boards nano Blink.ino
$ auniter verify nano Blink.ino
```

### Subcommand: Upload

To upload the sketch to the Arduino board, we need to provide the `--port`
flag. The following examples are all equivalent:

```
$ auniter upload --port /dev/ttyUSB0 \
    --board arduino:avr:nano:cpu=atmega328old Blink.ino
$ auniter upload --boards nano:USB0 Blink.ino
$ auniter upload nano:USB0 Blink.ino
```

### Subcommand: Test

To run the AUnit test and verify pass or fail:
```
$ auniter test --port /dev/ttyUSB0 \
    --board arduino:avr:nano:cpu=atmega328old tests/*Test
$ auniter test --boards nano:USB0 tests/*Test
$ auniter test nano:USB0 tests/*Test
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

### Automatic Directory Expansion

If the `auniter.sh` is given a directory `dir`, it tries to find
an ino file located at `dir/dir.ino`, since the ino file must have the
same base name as the parent directory.

Multiple files and directories can be given. The Arduino Commandline will
be executed on each of the ino files in sequence.

### Subcommand: Monitor

The serial port of the board can be monitored using the `monitor` subcommand. It
needs to know the tty serial port which can be given in any of the following
equivalent ways:
```
$ auniter monitor nano:USB0
$ auniter monitor --port /dev/ttyUSB0
$ auniter monitor /dev/ttyUSB0
$ auniter monitor USB0
```

The speed of the serial port can be given by the `--baud` flag.
The default is 115200, but you can change it like this:
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

Then add the following proerty in the `[auniter]` section of your `auniter.conf`
file:
```
[auniter]
  monitor = picocom -b $baud --omap crlf --imap lfcrlf --echo $port
```

The `auniter.sh` script will fill in the `$baud` and `$port` and execute the
command given in the config file. (The exit command for `picoterm` is `Ctrl-a
Ctrl-q` but if you are in a terminal multiplexer like `screen`, then `Ctrl-a` is
the escape character for `screen` itself, you have to type `Ctrl-a a Ctrl-q`
instead.)

### Upload and Monitor

Often we want to upload a program then immediately monitor the serial port, to
view the serial port output, or to send commands to the board over the serial
port. You do that using this shell one-liner:
```
$ auniter upload nano:USB0 Blink.ino && auniter monitor USB0
```

The `&&` operator causes the `monitor` program to run only if the `upload`
command was successful.

(I may create a new subcommand that implements this compound statement directly
into the `auniter.sh` script in the near future.)

### Multiple Boards

The `--boards` flag accepts a comma-separated list of `{alias}[:{port}]` pairs.

```
$ auniter verify nano,leonardo,esp8266,esp32 BlinkTest.ino
```

If you want to run the AUnit tests on multiple boards, you must provide the
port of each board, like this:
```
$ auniter test \
    nano:USB0,leonardo:ACM0,esp8266:USB2,esp32:USB1 \
  CommonTest DriverTest LedMatrixTest RendererTest WriterTest
```

There are no provision for creating aliases for the ports in the
`$HOME/.auniter.conf` file because the serial port is assigned by the OS and can
vary depending on the presence of other USB or serial devices.

### Mutually Exclusive Access (--locking, --nolocking)

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
$ auniter --exclude none --boards esp8266 CapacitiveButton
```

## Integration with Jenkins

I have successfully integrated `auniter.sh` into a locally hosted
[Jenkins](https://jenkins.io) Continuous Integration platform. The details are
given in the [Continuous Integration with Jenkins](jenkins) page.

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
$ auniter verify nano $(find -name '*.ino')
```

## Limitations

[Teensyduino](https://pjrc.com/teensy/teensyduino.html) is not
currently supported because of Issue #4.
