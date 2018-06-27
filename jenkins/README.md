# Continuous Integration with Jenkins

[Jenkins](https://jenkins.io) is a software automation tool for continuous
integration (CI) and continous deployment (CD). It has a master/slave
architecture with the master handing off jobs to worker slaves. In a small
configuration, the master can run on the local machine with no slaves and
execute all jobs by itself.

The [AUniter](https://github.com/bxparks/AUniter) scripts can be configured to
run from Jenkins so that the Arduino command line runs periodically (or upon
source code change) and the results will be tracked by Jenkins and displayed on
the Jenkins dashboard. If unit tests are written in
[AUnit](https://github.com/bxparks/AUnit) and an Arduino board is connected to
the local machine, the `auniter.sh` can upload the unit test to the board,
and monitor the serial port to determine if the test passed or failed,
and the results can be tracked on the Jenkins dashboard.

## Installation

The following installation instructions are known to work on:

* Ubuntu 17.10
* Ubuntu 18.04 (minimal desktop install)
* Xubuntu 18.04 (minimal desktop install)

Other Linux installations may also work but I have not verified them.

### Pre-requisite

Jenkins is Java app that requires the Java runtime to be installed. Only
Java 8 is supported. (The Arduino IDE is also a Java app, but it seems to be
bundled with its own Java runtime engine, so doesn't require additional
packages.)

Install the Open JDK 8 runtime:
```
$ sudo apt install openjdk-8-jdk
```

### Install Jenkins

Jenkins can be run as a Docker service, or as a normal Linux service.
For the integration with `AUniter` and the Arduino IDE, we will run
it as a normal Linux service.

The normal Ubuntu 18.04 `apt` repository has Jenkins version 2.121.1, so you
can just type:
```
$ sudo apt install jenkins
```

If you are on an older Ubuntu, or want to use the latest Jenkins version
(2.129 as if this writing), then you can following the
[Jenkins install instructions](https://jenkins.io/doc/book/installing/#debian-ubuntu):
```
$ wget -q -O - https://pkg.jenkins.io/debian/jenkins.io.key | sudo apt-key add -
$ sudo sh -c 'echo deb http://pkg.jenkins.io/debian-stable binary/ > /etc/apt/sources.list.d/jenkins.list'
$ sudo apt-get update
$ sudo apt-get install jenkins
```

### Allow Jenkins to Access the Serial Ports

If you want Jenkins to be able to upload Arduino programs to a board, the
Jenkins service must be given permission to the serial ports. The Jenkins
service runs as user `jenkins` (which was auto-created by the package
installer). We need to add that user to the group `dialout` which owns the
various serial port devices:

```
$ sudo usermod -a -G dialout jenkins
```

You then need to stop and start the Jenkins service by using the `systemctl`
command:
```
$ sudo systemctl restart jenkins
```

Note: You can check the status of the Jenkins service using
```
$ sudo systemctl status jenkins
```

### Install Arduino IDE into Jenkins

We will now give Jenkins its own copy of the Arduino IDE. Although it's more
work, it has the advantage that the Jenkins service becomes more independent of
the configuration changes of your copy of the Arduino IDE. (The other reason to
do this is because I was unable to make Jenkins use my personal copy of Arduino.
Almost everything worked, except that when the Arduino IDE saves its
preferences, the `preferences.txt` file is saved with its file mode set to
`600`, which prevents any other user on the computer from accessing that
preferences file.)

We are make some changes to the instructions for installing the
[Arduino IDE on Linux](https://www.arduino.cc/en/Guide/Linux), because
we will install it as a
[Portable IDE](https://www.arduino.cc/en/Guide/PortableIDE) into
the home directory of the user `jenkins`:

1. Download the latest 64-bit version of the tar.xz file (currently version
1.8.5). Take note of the location of the download file, it will be something
like `/home/{yourusername}/Downloads/arduino-1.8.5-linux64.tar.xz`.

2. Become user `jenkins` and install (i.e. un-tar) the IDE in its home directory
(`/var/lib/jenkins`):
```
$ sudo -i -u jenkins`
jenkins$ tar -xf * /home/{yourusername}/Downloads/arduino-1.8.5-linux64.tar.xz
jenkins$ cd arduino-1.8.5
jenkins$ mkdir portable
```
(You do *not* need to run the `./arduino-1.8.5/install.sh` command because it
doesn't do much except install desktop icons which will not be used by the
Jenkins service.)

3. Update the AVR boards and libraries
```
jenkins$ ./arduino --install-boards arduino:avr
```
These extra files will be stored under the `arduino-1.8.5/portable/` directory,
not in the `/var/lib/jenkins/.arduino15/` folder because of the existance
of the `portable/` directory.

4. (Optional) Install any other boards that you use. For example, to install the
[ESP8266 boards](https://github.com/esp8266/Arduino/blob/master/doc/installing.rst):
```
jenkins$ echo 'boardsmanager.additional.urls=http://arduino.esp8266.com/stable/package_esp8266com_index.json' \
>> portable/preferences.txt
jenkins$ ./arduino --install-boards esp8266:esp8266
```

5. (Optional) If you use the ESP32 board, install it using a modified form of
the [ESP32 install instructions](https://github.com/espressif/arduino-esp32):

```
$ sudo apt install git python python-pip python-serial
$ sudo -i -u jenkins
jenkins$ mkdir -p arduino-1.8.5/hardware/espressif
jenkins$ cd arduino-1.8.5/hardware/espressif
jenkins$ git clone https://github.com/espressif/arduino-esp32.git esp32
jenkins$ cd esp32
jenkins$ git submodule update --init --recursive
jenkins$ cd tools
jenkins$ python2 get.py
```

6. (TODO) Add instructions for installing Teensyduino

You might get some validation of a correct install by dumping the prefs:
```
jenkins$ cd
jenkins$ arduino-1.8.5/arduino --get-pref
```
An incorrect install of board files will show up as an error near the top of
this print out.

7. The set up is finished. Log out of the user `jenkins` from the shell.

## Configure Jenkins

The Jenkins service presents a web tool at http://localhost:8080.
* Point your web brower to that URL. It will ask for a secret token that was
  created by the installer located at
  `/var/lib/jenkins/secrets/initialAdminPassword` to verify that you have root
  access on your machine.
* Click on the large "Install suggested plugins" button to install all
  the recommended plugins. (This will take several minutes).
* Follow the instructions on the web tool to create the "First Admin User
  account for yourself. Click "Save and Continue".
* On the next page, you can leave the Jenkins URL to be "http://localhost:8080"
  if you are going to be accessing the Jenkis web tool only from the local
  machine. Click "Save and Finish".
* Click "Start using Jenkins" button. It will redirect you to the main
  http://localhost:8080 login page.
* Log in to the Jenkins web tool using that account.

NOTE: If http://localhost:8080/ shows you a blank page, try going to
http://localhost:8080/view/all/ instead. It seems like Jenkins was designed to
be used behind a reverse proxy and using `localhost` seems to mess up something.
I haven't spent a lot of time figuring this out. If you have access to your DNS
server, and you can access your machine using a DNS name, then you can set the
Jenkins URL (Manage Jenkins > Configure System > Jenkins Location > Jenkins URL)
to be `http://{yourmachine}:8080`.

## Tutorial: Creating a Jenkins Pipeline

This section is a tutorial on how to create a new Jenkins pipeline. A "pipeline"
is a Jenkins term for a set of tasks, that will include compiling, uploading and
testing one or more Arduino sketches. I have created a Jenkins pipeline for the
[AceButton](https://github.com/bxparks/AceButton) library, the first Arduino
library that I ever wrote, which provides button debouncing and event
dispatching.

1. Clone the `AceButton` git repository. Here, I will assume that your
git repository is located in the `$HOME` directory. If you generally keep
your git repos somewhere else, just `cd` to that directory before running
the following commands, and everything should be just fine, as long as you
remember to use the correct paths.

```
$ cd
$ git clone https://github.com/bxparks/AceButton.git
```
By default, you will be in the 'develop` branch of this project.

2. Create a new Pipeline using the Jenkins web tool:

* Goto http://localhost:8080, and log in using your user account.
* Click "New Item" on the left side.
* Under "Enter an item name", type "AceButtonPipeline". (I added the suffix
"Pipeline" to the name to avoid confusion because too many things are
named "AceButton" otherwise.)
* Click "Pipeline" option
* Click "OK".

![New Pipeline](NewItem-AceButtonPipeline.png)

3. Configure the pipeline

* Scroll down to the bottom of the configuration page, to the "Pipeline"
  section.
    * In the "Definition" section, select "Pipeline script from SCM". (This
      refers to the `Jenkinsfile` that's checked into the `AceButton/tests`
      directory.)
        * In the "SCM" section, select "Git".
            * In the "Repositories" section, fill in the following:
                * In the "Repository URL", enter the full path of the 
                  AceButton git repository that you cloned. In other words, it
                  will be something like `/home/{yourlogin}/AceButton`.
                * Leave the "Credentials" as "-none-" since Jenkins
                  does not need any special permission to access your directory.
            * In the "Branches to build" section, fill in the following:
                * In the "Branch Specifier", replace "*/master" with "*/develop"
                  to indicate that you will be compiling the `develop` branch.
            * In the "Additional Behaviours" section:
                * Click on the drop down menu labeled "Add", and select
                  "Check out to a sub-directry".
                * Then in the "Local subdirectory for repo" box, type in
                  "libraries/AceButton".
        * In the "Script Path" box, replace "Jenkinsfile" with
          "tests/Jenkinsfile".

![Pipeline configuration image](PipelineConfiguration.png)

4. Start the Build process

* Click "Build Now" menu on the left nav bar.

If everything works ok, then you should see a table that fills in
as the build progresses along. If all 5 stages complete (most likely
the last stage 'Test' will fail for you), you should see this:

![Stage View image](StageView.png)

Most likely, the last step 'Test' failed because you not have an Arduino
Nano board attached to your `/dev/ttyUSB0` port. In that case, you probably
saw this instead:

![Stage View failed image](StageViewFailedTest.png)

The `AceButton/tests/Jenkinsfile` file contains 4 stages:
* Setup - checkout source from github
* Verify Examples - verify `AceButton/examples/*` compile
* Verify Tests - verify `AceButton/examples/*` compile
* Test - upload `AceButton/tests/*Test` to an Arduino Nano board connected
to `/dev/ttyUSB0`, run the AUnit tests, and verify that they pass or fail

Normally, you would first verify that the `auniter.sh --test` works successfully
when you run it on the commmand line. If it works on the command line, then
Jenkins should be able to use the same command in the `Jenkinsfile`.

## Additional Features

### Build When Something Changes

You can configure the Jenkins pipeline to poll the SCM (i.e. the local git
repository) and automatically fire off a pipeline when it detects a change.

* Click on the "Configure" link of the "AceButtonPipeline" pipeline on the left
nav bar.
* Under the "Build Triggers", check the box for "Poll SCM".
    * For the "Schedule" edit box that opens up, type `H/5 * * * *`. This
      tells Jenkins to poll the local git repository every 5 minutes, and
      kick off a pipeline if something changed. It does nothing if nothing
      changed.

![Build Trigger Poll SCM](BuildTrigger-PollSCM.png)

### Install Blue Ocean Plugin

The [Blue Ocean](https://jenkins.io/doc/book/blueocean/getting-started/) plugin
for Jenkins implements the next generation UI for managing and
visualizing the pipelines. It can be installed from inside Jenkins by going to
"Main > Manage Jenkins > Manage Plugins > Available". Then Filter by "blue
ocean", select the plugin, and click "Install without restart". The download may
take several minutes.

### Email Notifications

Jenkins is extremely flexible and configurable. You can figure it to
send you emails if something goes wrong. (I haven't done this because I don't
install mailer programs on my Linux machine, so I'll leave this as an exercise
for the reader.)
