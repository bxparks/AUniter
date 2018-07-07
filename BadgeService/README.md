# AUniter Badge Service

(Work in progress)

## Introduction

[Continuous Integration with Jenkins](../jenkins/README.md) explains that
AUniter can be used by a locally hosted instance of
[Jenkins](https://jenkins.io). It has become popular to display
the current status of the continuous integration using
[GitHub badges](https://tygertec.com/add-badges-github-project/).

If the continuous integration service was running in the cloud
and publically accessible (e.g.
[Travis](https://travis-ci.org),
[CircleCI](https://circleci.com)),
and integrated with
[shields.io](https://github.com/badges/shields),
you could just add a simple shields.io URL into your README.md file to embed the
badge. Shields.io knows how to query the status of a number of Continuous
Integration services, and extract the correct information. However, our Jenkins
server runs on a local host, behind a firewall, so shields.io cannot reach it.

If GitHub had a mechanism to hold a small bit of user-defined parameter, and if
it had a way to dynamically generate a URL into the README.md based on the
user-defined parameter, we could let the GitHub markdown generator to generate
this badge for us. But as far as I can tell, GitHub does not provide such
functionality.

## A Micro Badge Service

The **BadgeService** is a micro web server using
[Google Cloud Functions](https://cloud.google.com/functions/) whose
sole job is to return a badge given the state of a build of a given
project. The state of the build is stored as zero-length files on
[Google Cloud Storage](https://cloud.google.com/storage/)
(Google's file system in the cloud). These files can be created and
modified by a shell script, which can be called from a
[Jenkinsfile](https://jenkins.io/doc/book/pipeline/jenkinsfile/)
by the locall hosted Jenkins server.

An example might make this more clear. 
For the [AceSegment](https://github.com/bxparks/AceSegment) project,
I created a **BadgeService** at
https://us-central1-xparks2015.cloudfunctions.net/badge?project=AceSegment.
This microservice looks for two files in Google Cloud Storage:
* `gs://xparks-jenkins/AceSegment=PASSED`, or
* `gs://xparks-jenkins/AceSegment=FAILED`.

If it finds a file named `AceSegment=PASSED`, the **BadgeService** returns
a green "passing" badge from shields.io. If it detects a file named
`AceSegment=FAILED`, it returns a red "failure" badge from shields.io.

The **BadgeService** *proxies* the content of the badge instead of returning
a 302 (or 307) redirect. In other words, the microservice fetches the image from
shields.io, then returns the content of image to the requester. It needs to
do this because shields.io sets the cache for static images to be 1 day, which
causes GitHub to generate a cached image of that badge which doesn't expire for
an entire day.

## Architecture Diagram

Here's a dependency diagram which might make this more clear:
```
      Google Cloud    shields.io
        Storage            ^
          ^   ^           /
          |    \         /
 (create/ |     \       / (GET badge)
  remove  |      \     /
  marker  |     BadgeService
  files)  |         ^
          |         | (embedded
          |         |  image)
          |         | 
          |       GitHub
----------|----  README.md
 firewall |         ^
          |         |
      local         | (GET)
      Jenkins       |
      service      user
```

Since shields.io cannot contact the local Jenkins serice, and neither can the
**BadgeService**, we use Google Cloud Storage as an intermediary to store the
state of the build.

## Setup Instructions

(TODO: Need to flush this out)

### Setup Badge Service

1. Download and install [Google Cloud SDK](https://cloud.google.com/sdk/).
1. Create project.
    * Enable billing.
    * Add Google Functions API.
1. Install `gsutil` for user `jenkins`.
    * `$ sudo -i -u jenkins`
    * `$ cd`
    * Install [standalone gsutil](https://cloud.google.com/storage/docs/gsutil_install)
    1. Authenticate using OAuth2 (`gsutil config`)
1. Create Google Cloud Storage bucket
1. Git clone AUniter project.
1. Configure the `bucketName` in `index.js` with the bucket name.
1. Upload Google Functions.
    * `$ gcloud functions deploy badge --trigger-http`
1. Create `gs://{bucketName}/test=PASSED`.
    * Goto https://{path-to-badge-server}?project=test
    * Verify got green badge.
1. Create `gs://{bucketName}/test=FAILED`.
    * Goto https://{path-to-badge-server}?project=test.
    * Verify got red badge.
1. Insert `![Alt Text](https://{path-to-badge-service}?project={project}]` in
   README.md

### Setup Jenkinsfile

The Jenkins file contains these additional `post` section, right after
the `stages` section:
```
post {
    failure {
        script {
            if (env.BADGE_BUCKET?.trim()) {
                sh "AUniter/BadgeService/set-badge-status.sh \
                    $BADGE_BUCKET AceSegment FAILED"
            }
        }
    }
    success {
        script {
            if (env.BADGE_BUCKET?.trim()) {
                sh "AUniter/BadgeService/set-badge-status.sh \
                    $BADGE_BUCKET AceSegment PASSED"
            }
        }
    }
}
```

### Setup Jenkins Pipeline

1. Add "BADGE_BUCKET" build parameter.
    * `{Name of Pipeline} > Configure > This project is parmeterized`
    * `Add Parameter > String Parameter`
    * `BADGE_BUCKET`: {name of GCS bucket}

### Security

* The Google Cloud Storage bucket does not need to be publically visible.
* The **BadgeService** runs with your credentials so it is able to access the
  GCS bucket.
* The badge URL takes a `project` parameter so someone could insert an
  arbitrary project name in there and determine the existence of certain files.
  However, the GCS bucket is *only* used for maintaining continuous integration
  build statuses, so this leakage of information has no consequences.
