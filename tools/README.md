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

The `auniter.sh` script uses the `$HOME/.auniter.ini` config file to
define named *environments* that correspond to specific hardware devices.
The environment `NAME` is used to control the target build flags and options.
The config file also allow mapping of a short alias (e.g. `uno`) to the fully
qualified board name (`fqbn`) used by the arduino binary (e.g.
`arduino:avr:uno`).

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
    * installation: `sudo apt install python3 python3-pip python3-serial`
* terminal program (for `auniter monitor` functionality)
    * [picocom](https://linux.die.net/man/8/picocom)
        * tested with v2.2
        * installation: `sudo apt install picocom`
    * [microcom](http://manpages.ubuntu.com/manpages/bionic/man1/microcom.1.html).
        * tested with v2016.01.0
        * installation: `sudo apt install microcom`

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
alias auniter='{path-to-auniter-directory}/tools/auniter.sh'
```
Don't add `{path-to-auniter-directory}/tools` to your `$PATH`. It won't work
because `auniter.sh` needs to know its own install directory to find helper
scripts.

**(The rest of the document will assume that you have created this alias.)**

### Config File

The `auniter.sh` script looks for a config file named `$HOME/.auniter.ini` in
your home directory. The format of the file is the
[INI file](https://en.wikipedia.org/wiki/INI_file),
and the meaning of these properties will be explained below. This INI file has
evolved to be similar to the one used by [PlatformIO](https://platformio.org/)
with some major differences:
1. `auniter.ini` is far simpler and easier to use (but less flexible)
1. there is only one `auniter.ini` per user (shared among many projects and
  libraries), instead of one INI file per project as used by PlatformIO

For the purposes of this tutorial, copy the `sample.auniter.ini` file to
`$HOME/.auniter.ini`. For reference, here's the condensed version of the sample
with comments stripped out:
```ini
[auniter]
  monitor = picocom -b $baud --omap crlf --imap lfcrlf --echo $port

[boards]
  uno = arduino:avr:uno
  nano = arduino:avr:nano:cpu=atmega328old
  leonardo = arduino:avr:leonardo
  mega = arduino:avr:mega:cpu=atmega2560
  nodemcuv2 = esp8266:esp8266:nodemcuv2:CpuFrequency=80,FlashSize=4M1M,LwIPVariant=v2mss536,Debug=Disabled,DebugLevel=None____,FlashErase=none,UploadSpeed=921600
  esp32 = espressif:esp32:esp32:PartitionScheme=default,FlashMode=qio,FlashFreq=80,FlashSize=4M,UploadSpeed=921600,DebugLevel=none

[env:uno]
  board = uno
  preprocessor = -DAUNITER_UNO

[env:nano]
  board = nano
  preprocessor = -DAUNITER_NANO -DAUNITER_LEFT_BUTTON=2 -DAUNITER_RIGHT_BUTTON=3

[env:leonardo]
  board = leonardo
  locking = false
  preprocessor = -DAUNITER_LEONARDO

[env:esp8266]
  board = nodemcuv2
  exclude = AceButton/examples/CapacitiveButton
  preprocessor = -DAUNITER_ESP8266 -DAUNITER_SSID="MyWiFi" -DAUNITER_PASSWORD="mypassword"

[env:esp32]
  board = esp32
  exclude = AceButton/examples/CapacitiveButton
  preprocessor = -DAUNITER_ESP32 -DAUNITER_SSID="MyWiFi" -DAUNITER_PASSWORD="mypassword"
```

The examples below will use these settings.

## Usage

Type `auniter --help` to get the latest usage. Here is the summary portion
of the help message:
```
$ auniter --help
Usage: auniter.sh [-h] [flags] command [flags] [args ...]
       auniter.sh envs
       auniter.sh ports
       auniter.sh verify {env} files ...
       auniter.sh upload {env}:{port},... files ...
       auniter.sh test {env}:{port},... files ...
       auniter.sh monitor [{env}:]{port}
       auniter.sh upmon {env}:{port} file
[...]
```

The 7 subcommands (`envs`, `ports`, `verify`, `upload`, `test`, `monitor`,
`upmon`) are described below.

### Subcommand: envs

There are 5 environments defined in the `$HOME/.auniter.ini` file.
The `envs` command prints out the environments:
```
$ auniter envs
uno
nano
leonardo
esp8266
esp32
```

### Subcommand: ports

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

### Subcommand: verify

This command runs the Arduino IDE binary and verifies that the given program
files build successfully for the specified environment `{env}` which is
defined in the `.auniter.ini` file. The following example verifies that the
`Blink.ino` sketch compiles under the `nano` environment:

```
$ auniter verify uno Blink.ino
```

### Environment {env}

The **Environment** in `auniter.sh` represents the target build context. It is
meant to correspond directly to a specific hardware device, composed of a
microcontroller board along with additional peripherals (buttons, LEDs, OLEDs,
sensors). The environment is defined in `$HOME/.auniter.ini` as an INI file
section whose format is `[env:NAME]` where `NAME` is the identifier of the
environment. See the **Advanced Usage** section for a description of the various
parameters of this section.

### Subcommand: upload

To upload the sketch to the Arduino board, we need to provide the port
of the device. The syntax is:
```
$ auniter.sh upload {env}:{port},... files ...
```
The syntax of the `{port}` is described in detail below. Multiple `{env}:{port}`
pairs can be given as a comman-separated list. Multiple sketch files can be
given as a space-separated list (uploading multiple sketch files will not be
normally useful, but it is allowed to support the `test` subcommand below).

Here are some examples:

```
$ auniter upload uno:USB0 Blink.ino
$ auniter upload leonardo:/dev/ttyACM0 Blink.ino Clock.ino
```

### Port Specifier {port}

The serial port on a Linux machine is a file that has the form `/dev/ttyXXXn`,
for example `/dev/ttyUSB0`. For convenience, the repetitive `/dev/tty` part can
be omitted from the `{port}` specifier. In other words, you can type
`uno:USB0`, instead of `uno:/dev/ttyUSB0`.

### Subcommand: test

The `auniter test` command compiles the program, uploads it to the board defined
by the environment, then reads the serial output from the board, looking for
specific output from the [AUnit](https://github.com/bxparks/AUnit) test runner.
```
$ auniter test uno:USB0 *Test.ino
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

### Subcommand: monitor

The serial port of the board can be monitored using the `monitor` subcommand. It
needs to know the tty serial port which can be given in any of the following
equivalent ways:
```
$ auniter monitor USB0
$ auniter monitor uno:USB0
$ auniter monitor /dev/ttyUSB0
```

When the port is given as `{env}:{port}`, the `{env}` part is ignored. This
feature is useful in interactive mode, so that you can scroll through the shell
history and simply change the `auniter upload ...` to `auniter monitor ...`
without having to also remove the `{env}:` part.

The speed of the serial port is usually controlled by the program that is
running on the Arduino board (through the `Serial.begin(xxxx)` statement.
The port speed value can be given by the `--baud` flag. The default is 115200,
but you can change it like this:
```
$ auniter monitor --baud 9600 USB0
```

The `monitor` subcommand delegates the serial terminal functionality to a
user-defined program defined in the `auniter.ini` file. The program that works
well for me is the [picocom](https://linux.die.net/man/8/picocom) program. On
Ubuntu Linux, install it using:
```
$ sudo apt install picocom
```
Another program that seems to work fairly well is
[microcom](http://manpages.ubuntu.com/manpages/bionic/man1/microcom.1.html).

You can choose which terminal program to use by adding one of the following
`monitor` definition in the `[auniter]` section of the `.auniter.ini` file:
```ini
[auniter]
  monitor = picocom -b $baud --omap crlf --imap lfcrlf --echo $port
  monitor = microcom -s $baud -p $port
```

The `auniter.sh` script will fill in the `$baud` and `$port` and execute this
command. (Note: The exit command for `picocom` is `Ctrl-a Ctrl-q` but if you are
in a terminal multiplexer like `screen`, then `Ctrl-a` is the escape character
for `screen` itself, you have to type `Ctrl-a a Ctrl-q` instead.)

### Subcommand: upmon (Upload and Monitor)

Often we want to upload a program then immediately monitor the serial port, to
view the serial port output, or to send commands to the board over the serial
port. You can do that using the `upmon` command:
```
$ auniter upmon uno:USB0 Blink.ino
```

The argument list is very similar to `upload` except that `upmon` accepts
only a single `{env}:{port}` pair.

## Advanced Usage

The following features are useful if you are working with multiple board types,
and/or if you are using `auniter.sh` as the driving script for the
[Jenkins continuous integration](../jenkins).

### Environment Parameters

There are 4 parameters currently supported in an environment section:
```ini
[env:NAME]
  board = {alias}
  locking = (true | false)
  exclude = egrep regular expression
  preprocessor = space-separated list of preprocessor symbols
```

The `NAME` of the environment does *not* need to be the same as the board
`{alias}`, but if you have only one device of particular board, then it's
convenient to make them the same.

* `board`: The `board` parameter specifies a board alias which is defined in the
  `[boards]` section of the `.auniter.ini` config file. The board alias is a
  short form of the full specification of the target microcontroller. The full
  form is called the fully-qualified board name (`fqbn`).

  It can be quite cumbersome to determine this value. The easiest way is to set
  the "Show verbose output during compilation and upload" checkboxes in the
  Arduino IDE, then look for the value of the `-fqbn` flag generated in the
  debug output. Another way is to track down the `hardware/.../boards.txt` file
  (there may be several verisons), open it up, and try to reverse engineer the
  `fqbn` of a particular Arduino board.
* `locking`: The `locking` parameter defaults to `true` which should work
  for most boards. Some boards (e.g. Leonardo or the Pro Micro) uses
  a virtual serial port instead of a hardware USB-to-Serial converter chip.
  When a virtual serial port is used, the `auniter.sh` script is not able
  to lock the serial port properly to gain exclusive access. For these boards,
  the locking must be turned off.
* `exclude`: Files matching this regular expression are excluded from
  the build. This is intended to be used in continous integration scripts.
* `preprocessor`: This is a space-separated list of C preprocessor macros
  in the form of `MACRO`, `MACRO=value` or `MACRO="string value"`. The script
  automatically defines the macro `AUNITER` so that you can detect if the build
  was started by the `auniter.sh` script (as opposed to using the Arduino IDE.)

  There are 2 main use-cases for the `preprocessor` parameter. One, a given
  sketch file can be compiled on multiple environments with the unique macro for
  the environment (e.g. `AUNITER_{env}` activating different code paths. Two,
  passwords and other private information can be stored in the `.auniter.ini`
  file and injected into the code to prevent these secrets from being checked
  into the source code repository. (In GitHub, once a secret has been checked
  in, it is there forever).

### Automatic Directory Expansion

If the `auniter.sh` is given a directory `dir`, it tries to find
an ino file located at `dir/dir.ino`, since the ino file must have the
same base name as the parent directory.

Multiple files and directories can be given. The Arduino Commandline will
be executed on each of the ino files in sequence.

### Compiling to Multiple Environments

The `verify`, `upload` and `test` commands all support multiple board/port pairs
by listing them as a comma-separated list of `{env}:{port}`. For example, we
can compile (verify) a single sketch across multiple environments like this:

```
$ auniter verify uno,leonardo,esp8266,esp32 Blink.ino Timer.ino
```

The outer loop iterates over the environments, and the inner loop iterates
over the multiple files. (This allows the Arduino IDE to cache the temperary
objects generated by the compiler.)

If you want to run the AUnit tests on multiple environments, you must provide
the `{port}` of each `{env}`, like this:
```
$ auniter test uno:USB0,leonardo:ACM0,esp8266:USB2,esp32:USB1 \
  CommonTest DriverTest LedMatrixTest RendererTest WriterTest
```

There is no provision for creating aliases for the ports in the
`$HOME/.auniter.ini` file because the serial port is assigned by the OS and can
change frequently depending on the presence of other USB or serial devices.

### Mutually Exclusive Access (locking)

(Valid for subcommands: `upload`, `test`)

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

By default, the locking is enabled. To disable locking for a specific
environment, set the `locking` parameter to `false`, like this:
```ini
[env:leonardo]
  board = leonardo
  locking = false
```

### Excluding Files (exclude)

(Valid for subcommands: `verify`, `upload`, `test`.)

Some programs cannot be compiled under some microcontroller boards.
The `exclude` parameter causes any `*.ino` files whose fullpath matches this
[egrep](https://linux.die.net/man/1/egrep) regular expression to be skipped.

The `CapacitiveButton` program does not compile for ESP8266 or ESP32 boards.
This entry in the `CONFIG_FILE` will cause `auniter.sh` to skip this file for
all modes (verify, upload, test, monitor).

Multiple files can be specified using the `a|b` regular expression. For example:
```ini
[env:esp8266]
  board = esp8266
  exclude = AceButton/examples/CapacitiveButton|AceButton/examples/StopWatch
```

### Config File (--config)

(Valid on the `auniter.sh` command.)

By default, the `auniter.sh` script looks in the
```
$HOME/.auniter.ini
```
file in your home directory. The script can be told to look elsewhere using the
`--config` command line flag. (Use `--config /dev/null` to indicate no config
file.) This may be useful if the config file is checked into source control for
each Arduino project.

```
$ auniter --config {path-to-config-file} subcommand {env}:{port} ...
```

(The `--config` flag is an option on the `auniter.sh` command, not the
subcommand, so it must occur *before* the subcommands.)

### Verbose Mode (--verbose)

(Valid on the `auniter.sh` command)

The `auniter.sh` accepts a `--verbose` flag, which enables verbose mode for
those subcommands which support it. In particular, it is passed into the Arduino
binary, which then prints out the compilation steps in extreme detail.

### Default Baud Rate (baud, --baud)

(Valid for subcommands: `monitor` and `upmon`)

If the `--baud` flag is not given for the `monitor` or `upmon` commands,
then the default baud rate for the serial port is set to `115200`. You can
change this default value in the `.auniter.ini` file using the `baud` property
in the `[auniter]` section. For example, the following sets the default baud
rate to 9600:
```ini
[auniter]
  baud = 9600
```

### Skip Missing Port (--skip_missing_port)

(Valid for subcommands: `upload` and `test`)

Normally the `verify`, `upload` and `test` commands will fail with an error
message if the `{port}` specifier is not given. However, in continuous
integration scripts, it is useful to simply skip the operation if the port is
missing. This flag turns on that feature.

### Sketchbook Path (--sketchbook)

In continuous integration scripts, the root path of the sketchbook needs to be
changed to a directory where the various libaries have been checked out. This
flag changes the sketchbook directory of the Arduino IDE.

## Integration with Jenkins

I have successfully integrated `auniter.sh` into a locally hosted
[Jenkins](https://jenkins.io) Continuous Integration platform. The details are
given in the [Continuous Integration with Jenkins](../jenkins) page.

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

### Using Both Arduino IDE and the AUniter Script

If you compile a program using the `auniter.sh` script, you can use the
`preprocessor` parameter in the given `[env:NAME]` section to define a
C-preprocessor symbol that will let you customize the sketch for a specific
target environment. For example in the
[sample.auniter.ini](sample.auniter.ini) file, the `nano` environment
defines the `AUNITER_NANO` preprocessor macro, so that you can do
something like:
```c++
#if defined(AUNITER_NANO)
  ...
#elif defined(AUNITER_ESP8266)
  ...
#else
  #error Unsupported AUNITER environment
#endif
```

There are 2 problems with the above code:
1. If your program is composed of multiple files (one `*.ino`, and
several `*.cpp` and `*.h` files), then you need to replicate those
lines for each file where you need to do different things for different
target enviroments.
1. If you compile your program with the Arduino IDE, none of these `AUNITER_*`
macros are defined, so you will hit the `#error` message.

The recommended solution is to create a `config.h` file that centrallizes
the dependencies on a particular AUniter target environment, and use `#include`
to include that file in other `*.h` and `*.cpp` files. The macro `AUNITER` is
the one macro that is automatically defined when the `auniter.sh` script is used
to compile the program. This can be used to determine whether or not you are
compiling using the Arduino IDE, instead of using `auniter.sh`. (All other
macros must be explicitly defined in the `preprocessor` parameters of the
`[env:NAME]` section of the ini file.)

Putting all this together, the `config.h` would look like this:

```c++
#ifndef MY_PROJECT_CONFIG_H
#define MY_PROJECT_CONFIG_H

#if !defined(AUNITER)
  // Compiling under Arduino IDE directly, so define a default environment.
  #define AUNITER_MICRO
  #warning Defaulting to AUNITER_MICRO
#endif

#if defined(AUNITER_MICRO)
  #define FEATURE_ONE ...
  #define FEATURE_TWO ...
#elif defined(AUNITER_NANO)
  #define FEATURE_ONE ...
  #define FEATURE_TWO ...
...
#else
  #error Unsupported AUNITER environment
#endif

#endif
```

In all the other `*.cpp` and `*.h` files, you would just do:
```c++
#include "config.h"
```


## Limitations

[Teensyduino](https://pjrc.com/teensy/teensyduino.html) is not
currently supported because of Issue #4.
