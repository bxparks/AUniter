/**
 * Copyright 2018 Brian T. Park
 * MIT License
 *
 * Looks for the presence of a file in the given 'bucketName'. The filename
 * has the form:
 *    - {project}-PASSED
 *    - {project}-FAILED
 *
 * If the PASSED file is detected, then a "passing" badge from shields.io is
 * returned with a 302 redirect. If the FAILED file is detected, a "failure"
 * badge from shields.io is returned.
 */

'use strict';

// NOTE: Change these parameters to match your Google Cloud Storage
// configuration.
const bucketName = 'xparks-jenkins';
const project = 'AceButton'; // AceButton-PASSED, AceButton-FAILED

// Change this if you want longer checking intervals.
const checkIntervalMillis = 5 * 60 * 1000; // 5 minutes

const Buffer = require('safe-buffer').Buffer;

// Cache the result of checking for -PASSED or -FAILED files.
var passedFound = false;
var failedFound = false;
var lastCheckedTime = 0;

/**
 * Check for the presence of the {project}-PASSED or {project}-FAILED files
 * in the Google Cloud Storage bucket named {bucketName}.
 */
function checkPassOrFail() {
	const Storage = require('@google-cloud/storage');
	const storage = new Storage();

  storage
    .bucket(bucketName)
    .file('/' + project + '-PASSED')
    .getMetadata()
    .then(results => {
      const metadata = results[0];
      passedFound = true;
      console.log('checkPassOrFail(): PASSED found');
    })
    .catch(err => {
      passedFound = false;
      console.log('checkPassOrFail(): PASSED not found');
    });

  storage
    .bucket(bucketName)
    .file('/' + project + '-FAILED')
    .getMetadata()
    .then(results => {
      const metadata = results[0];
      failedFound = true;
      console.log('checkPassOrFail(): FAILED found');
    })
    .catch(err => {
      failedFound = false;
      console.log('checkPassOrFail(): FAILED not found');
    });
}

/**
 * HTTP Cloud Function which redirect to a "passing" badge or a "failure"
 * badge, depending on whether the {project}-PASSED or {project}-FAILED
 * files were found.
 *
 * @param {Object} req Cloud Function request context.
 * @param {Object} res Cloud Function response context.
 */
exports.badge = (req, res) => {
  var uri;
  if (passedFound) {
    if (failedFound) {
      uri = 'build-error-yellow.svg';
    } else {
      uri = 'build-passing-brightgreen.svg';
    }
  } else {
    if (failedFound) {
      uri = 'build-failure-brightred.svg';
    } else {
      uri = 'build-unknown-lightgrey.svg';
    }
  }
  
  var nowMillis = new Date().getTime();
  if (nowMillis - lastCheckedTime > checkIntervalMillis) {
    checkPassOrFail();
    lastCheckedTime = nowMillis;
    console.log("Calling checkPassOrFail");
  }

  res.redirect('https://img.shields.io/badge/' + uri);
};
