# AUniter Command Line Tools and Continuous Integration for Arduino

These are command line tools to easily build and upload multiple Arduino
programs for multiple microcontroller boards, validate unit tests written in
[AUnit](https://github.com/bxparks/AUnit),
and integrate with a locally hosted
[Jenkins](https://jenkins.io) continuous integration (CI) system.
A single command can compile and upload multiple programs for multiple boards.
This automation capability is fully utilized when running unit tests across
multiple target boards. A configuration file in
[INI file](https://en.wikipedia.org/wiki/INI_file)
format allows users to define short board aliases for the fully qualified board
names (`fqbn`) which can be awkwardly long for some boards (e.g. ESP8266 or
ESP32). Users can define target Environments in the configuration file
corresponding to specific hardware configurations described by its board alias
and other parameters such as optional C preprocessor macros.

This package provides command line scripting abilities without converting to a
vastly different build environment such as
[PlatformIO](https://platformio.org).
The underlying tool is a shell wrapper around the command line abilities built
right into the
[Arduino IDE](https://github.com/arduino/Arduino/blob/master/build/shared/manpage.adoc)
itself. Therefore, the AUniter package is able to support all boards, libraries,
and build configurations which are supported by the Arduino IDE. There is no
duplicate installs of boards and libraries because the build and upload steps go
through the Arduino IDE binary in command line mode.

There are 3 components to the **AUniter** package:

1. A command line tool [`tools/auniter.sh`](tools/) that can compile and upload
   Arduino programs. It can also upload unit tests written in
   [AUnit](https://github.com/bxparks/AUnit) and validate the success and
   failure of the unit tests.
1. A locally hosted [Jenkins Integration](jenkins/) to provide Ccontinuous
   Integration (CI) of unit tests upon changes to the source code repository.
    * This depends on the `auniter.sh` described above.
    * As of v1.8 or so, I no longer use this integration because:
        1. the Arduino IDE is simply too slow, with some of my projects taking
            1-2 hours to run through all the test suites,
        1. The Arduino-CLI tool cannot replace the Arduino IDE because its
            [broken --build-properties
            flag](https://github.com/arduino/arduino-cli/issues/846), and,
        1. The Jenkins service is too brittle and cumbersome to maintain.
    * I have started to use the
      EpoxyDuino (https://github.com/bxparks/EpoxyDuino) project
      more frequently as an alternative, even though it cannot handle the
      Arduino programs that depend on specific hardware.
1. A [Badge Service](BadgeService/) running on
   [Google Cloud Functions](https://cloud.google.com/functions/)
   that allows the locally hosted Jenkins system to update the status of the
   build, so that an indicator badge can be displayed on a source control
   repository like GitHub.
    * This depends on the Jenkins Integration described above.
    * As of v1.8 or so, I no longer use this service, because the Arduino IDE
      is too slow to handle the number of INO files that I needed to compile in
      my Continuous Integration pipeline. I may revisit this when Arduino-CLI
      fixes the broken parser of its `--build-properties` flag.

The `auniter.sh` script uses the command line mode of the
[Arduino IDE binary](https://github.com/arduino/Arduino/blob/master/build/shared/manpage.adoc).
Here are some tasks that you can perform on the command line using the
`auniter.sh` script (the following examples use the `auniter` alias for
`auniter.sh` for conciseness):

* `$ auniter envs`
    * list the environments configured in the `auniter.ini` config file
* `$ auniter ports`
    * list the available serial ports and devices
* `$ auniter verify nano Blink.ino`
    * verify (compile) `Blink.ino` using the `env:nano` environment
* `$ auniter verify nano,esp8266,esp32 Blink.ino`
    * verify `Blink.ino` on 3 target environments (`env:nano`, `env:esp8266`,
    `env:esp32`)
* `$ auniter upload nano:/dev/ttyUSB0 Blink.ino`
    * upload `Blink.ino` to the `env:nano` target environment connected to
    `/dev/ttyUSB0`
* `$ auniter test nano:USB0 BlinkTest.ino`
    * compile and upload `BlinkTest.ino` using the `env:nano` environment,
      upload it to the board at `/dev/ttyUSB0`, then validate the output of the
      [AUnit](https://github.com/bxparks/AUnit) unit test
* `$ auniter test nano:USB0,esp8266:USB1,esp32:USB2 BlinkTest/ ClockTest/`
    * upload and verify the 2 unit tests (`BlinkTest/BlinkTest.ino`,
      `ClockTest/ClockTest.ino`) on 3 target environments (`env:nano`,
      `env:esp8266`, `env:esp32`) located at the 3 respective ports
      (`/dev/ttyUSB0`, `/dev/ttyUSB1`, `/dev/ttyUSB2`)
* `$ auniter upmon nano:USB0 Blink.ino`
    * upload the `Blink.ino` sketch and monitor the serial port using a
      user-configurable terminal program (e.g. `picocom`) on `/dev/ttyUSB0`

The `auniter.sh` script uses an
[INI file](https://en.wikipedia.org/wiki/INI_file)
configuration file
normally located at `$HOME/.auniter.ini`. It contains various user-defined
configurations and aliases which look like this:
```ini
[auniter]
  monitor = picocom -b $baud --omap crlf --imap lfcrlf --echo $port

[boards]
  uno = arduino:avr:uno
  nano = arduino:avr:nano:cpu=atmega328old
  leonardo = arduino:avr:leonardo
  promicro16 = SparkFun:avr:promicro:cpu=16MHzatmega32U4
  mega = arduino:avr:mega:cpu=atmega2560
  nodemcuv2 = esp8266:esp8266:nodemcuv2:CpuFrequency=80,FlashSize=4M1M,LwIPVariant=v2mss536,Debug=Disabled,DebugLevel=None____,FlashErase=none,UploadSpeed=921600
  esp32 = esp32:esp32:esp32:PartitionScheme=default,FlashMode=qio,FlashFreq=80,FlashSize=4M,UploadSpeed=921600,DebugLevel=none

[env:uno]
  board = uno
  preprocessor = -DAUNITER_UNO

[env:nano]
  board = nano
  preprocessor = -DAUNITER_NANO -DAUNITER_LEFT_BUTTON=2 -DAUNITER_RIGHT_BUTTON=3

[env:micro]
  board = promicro16
  locking = false
  preprocessor = -DAUNITER_MICRO -DAUNITER_BUTTON=3
```

**Version**: 1.9 (2020-12-03)

**Changelog**: [CHANGELOG.md](CHANGELOG.md)

## Installation

1. See [AUniter Tools](tools/) to install the `auniter.sh` command line tools.
1. See [AUniter Jenkins Integration](jenkins/) to integrate with Jenkins.
1. See [AUniter Badge Service](BadgeService/) to display the
   build status in the source repository.

## System Requirements

* **AUniter Tools** require the following:
    * Linux
        * tested on Ubuntu 16.04, 17.10, 18.04, 20.04
    * MacOS
        * tested on 10.14.6 (Mojave)
        * *not* tested on 10.15 (Catalina)
        * requires GNU coreutils
        * requires GNU gsed
    * Arduino IDE
        * tested on 1.8.5, 1.8.6, 1.8.7, 1.8.9, 1.8.13
* **AUniter Jenkins Integration** requires the following:
    * **AUniter Tools**
    * [AUnit](https://github.com/bxparks/AUnit) (optional)
    * [Jenkins](https://jenkins.io) Continuous Integration platform
    * Linux system (tested on Ubuntu 16.04, 17.10, 18.04)
* **AUniter BadgeService** requires the following:
    * **AUniter Integration with Jenkins**
    * [Google Cloud Services](https://cloud.google.com/) account
    * [Google Functions](https://cloud.google.com/functions/)

Windows is definitely not supported because the scripts require the `bash`
shell. I am not familiar with
[Windows Subsystem for Linux](https://docs.microsoft.com/en-us/windows/wsl/install-win10)
so I do not know if it would work on that.

## Limitations

* [Teensyduino](https://pjrc.com/teensy/teensyduino.html) is not supported
  due to [Issue #4](https://github.com/bxparks/AUniter/issues/4).
* Arduino-CLI has a broken parser for its `--build-properties` flag, so
  `-D` flags with a string does not work.

## Alternatives Considered

There are a number of other command line solutions for building and running
Arduino programs. None of them had all the features that I wanted:

* ability to define short board aliases (e.g. `nodemcuv2`) for long
  fully qualified board names (e.g.
  `esp8266:esp8266:nodemcuv2:CpuFrequency=80,FlashSize=4M1M,LwIPVariant=v2mss536,Debug=Disabled,DebugLevel=None____,FlashErase=none,UploadSpeed=921600`)
* ablility to upload an AUnit unit test to a target board, then validate
  the output of the serial port for success or failure of that unit test
* ability to build and upload a single sketch against multiple boards
* ability to build and upload multiple sketches (e.g. unit tests) to a single
  board
* ability to define "environments" which include the board alias, and
  C preprocessor macros (PlatformIO has this)
* support for continuous build and test interation (PlatformIO has this but
  is a paid feature)

However, I was inspired by various features of all of the following
alternatives.

### Arduino IDE Command Line

The
[Arduino IDE binary](https://github.com/arduino/Arduino/blob/master/build/shared/manpage.adoc).
supports a command line mode where the application runs in a headless mode and
run commands given as flags. The `auniter.sh` script is essentially a giant
wrapper around the Arduino IDE binary. The motiviation for writing the wrapper
was the following:

* The Arduino IDE command line flags are long, cumbersome and hard to remember.
* The Arduino IDE command line uses fully qualified board names (`fqbn`) which
  are sometimes incredibly long (e.g. ESP8266 and ESP32). I wanted to support
  user-defined board aliases.
* The Arduino IDE command line does not know anything about unit tests
  written in AUnit. I wanted a single command that would upload and validate
  the unit test for success or failure.

### AMake

The [amake](https://github.com/pavelmc/amake) tool is very similar to
`auniter.sh`. It is a shell script that calls out to the Arduino commandline.

There are a few features of `amake` that I found problemmatic for my purposes.
* Although `amake` supports the concept of board aliases, the aliases are
  hardwared into the `amake` script itself. I felt that it was important to
  allow users to define their own board aliases (through the `.auniter.ini`
  dotfile).
* `amake` saves the information about the most recent `*.ino` file and
  board type in a cache file named `.amake` in the current directory. This was
  designed to make it easy to compile and verify a single INO file repeatedly.
  However, `auniter.sh` is designed to make it easy to compile, upload, and
  validate multiple `*.ino` files, on multiple Arduino boards, on multiple
  serial ports.

### Arduino-CLI

The [Arduino CLI](https://github.com/arduino/arduino-cli) is currently in alpha
stage. I did not learn about it until I had built the `AUniter` tools. It is a
Go Lang program which interacts relatively nicely with the Arduino IDE.

Version 1.8 includes an initial integration with Arduino-CLI and exposes
that functionality through the `--cli` flag. However, the Arduino-CLI has a
broken parser for its `--build-properties` flag, so it does not support `-D`
flags that contain strings.

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
(but I have not looked into how easy or hard that would be).

The problem with `Arduino-Makefile` is that it seems to allow only a single
board type target in the Makefile. Changing the target board would mean editting
the `Makefile`. Since I wanted to be able to easily compile, upload and validate
against multiple boards, the `Makefile` solution did not seem to be flexible
enough.

The second problem with `Arduino-Makefile` is that I prefer to avoid
`Makefile`s. I have used them in the past and find them difficult to debug and
maintain. The appeal of the Arduino development is that it is simple to use,
with few or no extraneous configuration files. I wanted to preserve that feature
as much as possible.

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

I think it would be feasible to integrate PlatformIO tools into a locally
running Jenkins service like I did with `auniter.sh`. However, I think it has
some disadvantages.
* It is a far more complex than the Arduino IDE, so the learning curve is
  longer.
* It seems that the `platformio.ini` file must be created for every unit of
  compilation and upload, in other words, for every `*.ino` file. This seems to
  be too much overhead when a project has numerous AUnit unit test files, each
  of them being a separate `*.ino` file.
* A new directory structure seems to be required for each `*.ino` file,
  with a separate `lib/` and a `src/` directory. Since every AUnit unit test is
  a separate `*.ino` file, the overhead for this directory structure seemed like
  too much work for a single unit test.

The `platformio.ini` files provide better isolation between `*.ino` files, but
the overhead seem too much for me.

### Arduino Builder

The [Arduino Builde](https://github.com/arduino/arduino-builder) seems to be a
collection of Go-lang programs that provide commandline interface for compiling
Arduino sketches. However, I have not been able to find any documentation that
describes how to actually to use these programs.

## License

[MIT License](https://opensource.org/licenses/MIT)

## Feedback and Support

If you have any questions, comments, bug reports, or feature requests, please
file a GitHub ticket or send me an email. I'd love to hear about how this
software and its documentation can be improved. Instead of forking the
repository to modify or add a feature for your own projects, let me have a
chance to incorporate the change into the main repository so that your external
dependencies are simpler and so that others can benefit. I can't promise that I
will incorporate everything, but I will give your ideas serious consideration.

## Authors

* Created by Brian T. Park (brian@xparks.net).
