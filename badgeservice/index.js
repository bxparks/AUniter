/**
 * Copyright 2018 Brian T. Park
 *
 * MIT License
 *
 * A Google Functions microservice which returns a shields.io badge depending
 * on the status of the Jenkins continuous integration of a given project.
 *
 * The GET handler is at:
 *  - https://us-central1-xparks2015.cloudfunctions.net/badge?project={project}
 * The {project} is the name of the project being queried.
 *
 * It looks for a status file in Google Cloud Storage, in the given
 * 'bucketName', with the form:
 *
 *  - '{project}=PASSED'
 *  - '{project}=FAILED'
 *
 * There are 4 possible badges:
 *
 *  - If the PASSED file is detected, then a "passing" badge from shields.io is
 *    returned.
 *  - If the FAILED file is detected, a "failure" badge from shields.io is
 *    returned.
 *  - If both of these marker files are miising, then an "unknown" badge is
 *    returned.
 *  - If both of these markers file exist (which shouldn't happen), then
 *    an "error" badge is returned.
 *
 * Deployment:
 *
 *  $ gcloud functions deploy badge --trigger-http
 */

'use strict';

// The Google Cloud Storage bucket name used to hold the continuous integration
// // (CI) test results. NOTE: Change this to your own bucket.
const bucketName = 'xparks-jenkins';

// Number of milliseconds between successive calls to checkPassOrFail().
const checkIntervalMillis = 1 * 60 * 1000;

const Buffer = require('safe-buffer').Buffer;

const badgeBaseUrl = 'https://img.shields.io/badge/';

// Cache of various meta-info related to the CI status of particular project.
var projectInfos = {};

// Time when the last check was performed.
var lastCheckedTime = 0;

/**
 * Check for the presence of the {project}=PASSED or {project}=FAILED files
 * in the Google Cloud Storage bucket named by bucketName.
 */
function updateProjectInfos(files) {
  console.log('updateProjectInfos(): processing ', files.length, ' files');
  const re = /(^[^= ]+)=([^= ]+)$/;
  files.forEach(file => {
    const m = file.name.match(re);
    if (m) {
      const projectName = m[1];
      projectInfos[projectName] = {
        passedFound: (m[2] == 'PASSED'),
        failedFound: (m[2] == 'FAILED')
      };
    }
  });
}

/**
 * Return the badge URI fragment of the project using the projectInfos cache.
 */
function getUri(project) {
  if (project == null) {
    return 'build-invalid-orange.svg';
  }

  const projectInfo = projectInfos[project];
  if (projectInfo == null) {
    return 'build-unknown-lightgrey.svg';
  } else {
    if (projectInfo.passedFound) {
      if (projectInfo.failedFound) {
        return 'build-error-yellow.svg';
      } else {
        return 'build-passing-brightgreen.svg';
      }
    } else {
      if (projectInfo.failedFound) {
        return 'build-failure-brightred.svg';
      } else {
        return 'build-unknown-lightgrey.svg';
      }
    }
  }
}

/**
 * Fetch the shields.io badge and echo it back to res. I tried using a 307
 * redirect, but shields.io returns a response with "cache-control:
 * max-age=86400" for static badges, which causes GitHub to cache the badge for
 * 1 whole day. To bypass the cache-control, we fetch it ourselves, then proxy
 * the image back the requester. Our header is set to "cache-control: no-cache,
 * must-revalidate" which is enough to prevent GitHub from permanently caching
 * that image. I also notice an "etag" header being set. That must be set
 * automatically by the Google Frontend in front of this service.
 *
 * For explanation of the https.get() and Promise chaining, see:
 *
 *  - https://nodejs.org/docs/latest/api/https.html.
 *  - https://javascript.info/promise-chaining
 *  - https://valentinog.com/blog/http-requests-node-js-async-await/
 */
function fetchBadge(res, url) {
  return new Promise((resolve, reject) => {
    var https = require('https');

    https.get(url, (http_res) => {
      const { statusCode } = http_res;
      if (statusCode !== 200) {
        console.log('fetchBadge(): statusCode: ', statusCode, '; url: ', url);
        http_res.resume();
        res.status(404).end();
        resolve();
        return;
      }

      var data = '';
      http_res.on('data', (chunk) => {
        data += chunk;
      });
      http_res.on('end', () => {
        res.type('image/svg+xml;charset=utf-8');
        res.send(data);
        resolve();
      });
    }).on('error', e => {
      console.error('ERROR: ', err);
      res.status(500).end();
      reject();
    });
  });
}

/**
 * HTTP Cloud Function which returns a badge from shields.io, depending on
 * whether the {project}=PASSED or {project}=FAILED files were found. The
 * entire GET request seems to take between 300-800 millis, even when the cache
 * is updated using updateProjectInfos().
 *
 * When multiple requests are made quickly, the service returns 304
 * automatically. (Not really sure where that happens, I'm guessing at the
 * Google Frontend just in front of this service.)
 *
 * @param {Object} req Cloud Function request context.
 * @param {Object} res Cloud Function response context.
 */
exports.badge = (req, res) => {
  const project = req.query.project;
  if (project == null) {
    return fetchBadge(res, badgeBaseUrl + 'build-invalid-orange.svg');
  }
  console.log('badge(): Processing project: ', project);

  // Use the cache if it was updated recently.
  const nowMillis = new Date().getTime();
  if (nowMillis - lastCheckedTime <= checkIntervalMillis) {
    const uri = getUri(project);
    return fetchBadge(res, badgeBaseUrl + uri);
  }

  const Storage = require('@google-cloud/storage');
  const storage = new Storage();

  // Update the cache, then return the results.
  return storage
      .bucket(bucketName)
      .getFiles()
      .then(results => {
        const files = results[0];
        updateProjectInfos(files);
        lastCheckedTime = nowMillis;
        const uri = getUri(project);
        return fetchBadge(res, badgeBaseUrl + uri);
      })
      .catch(err => {
        console.error('ERROR: ', err);
        res.status(500).end();
      });
};
