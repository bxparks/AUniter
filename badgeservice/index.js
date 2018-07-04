/**
 * Copyright 2018 Brian T. Park
 * MIT License
 *
 * The GET handler at
 *
 * https://us-central1-xparks2015.cloudfunctions.net/badge?project=AceButton
 *
 * looks for the presence of a file in the given 'bucketName', with the form:
 *
 *    - {project}-PASSED
 *    - {project}-FAILED
 *
 * If the PASSED file is detected, then a "passing" badge from shields.io is
 * returned with a 302 redirect. If the FAILED file is detected, a "failure"
 * badge from shields.io is returned.
 *
 * Multiple projects are supported using the 'project' query parameter.
 * The list of valid {project} are in the 'projects' variable below.
 * If the project does not match, then an "invalid" badge is returned.
 */

'use strict';

// The Google Cloud Storage bucket name used to hold the continuous integration
// test results. NOTE: Change this to your own bucket.
const bucketName = 'xparks-jenkins';

// List of acceptable projects. Anything that does not match returns
// an "invalid" badge. NOTE: Change this to your own list of projects.
const projects = ['AceButton'];

// Change this if you want longer or shorter checking intervals.
const checkIntervalMillis = 1 * 1000; // 5 minutes

const Buffer = require('safe-buffer').Buffer;

const badgeBaseUrl = 'https://img.shields.io/badge/';

// Cache of various info related to a particular project.
var projectInfos = {};

/**
 * Check for the presence of the {project}-PASSED or {project}-FAILED files
 * in the Google Cloud Storage bucket named {bucketName}.
 */
function checkPassOrFail(project) {
  if (projects.indexOf(project) < 0) {
    console.log('checkPassOrFail(): Unknown project: ', project);
    return;
  }
  console.log("checkPassOrFail(): project: ", project);

  var projectInfo = projectInfos[project];
  if (projectInfo == null) {
    console.log('checkPassOrFail(): projectInfo not found');
    return;
  }

	const Storage = require('@google-cloud/storage');
	const storage = new Storage();

  storage
    .bucket(bucketName)
    .file('/' + project + '-PASSED')
    .getMetadata()
    .then(results => {
      const metadata = results[0];
      projectInfo.passedFound = true;
      console.log('checkPassOrFail(): PASSED found');
    })
    .catch(err => {
      projectInfo.passedFound = false;
      console.log('checkPassOrFail(): PASSED not found');
    });

  storage
    .bucket(bucketName)
    .file('/' + project + '-FAILED')
    .getMetadata()
    .then(results => {
      const metadata = results[0];
      projectInfo.failedFound = true;
      console.log('checkPassOrFail(): FAILED found');
    })
    .catch(err => {
      projectInfo.failedFound = false;
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
  const project = req.query.project;
  if (project == null) {
    console.log('badge(): Missing project parameter');
    res.redirect(badgeBaseUrl + 'build-invalid-orange.svg');
    return;
  }
  if (projects.indexOf(project) < 0) {
    console.log('badge(): Invalid project: ', project);
    res.redirect(badgeBaseUrl + 'build-invalid-orange.svg');
    return;
  }
  console.log("badge(): Processing project: ", project);

  var projectInfo = projectInfos[project];
  if (projectInfo == null) {
    projectInfo = {
      passedFound: false,
      failedFound: false,
      lastCheckedTime: 0
    };
    projectInfos[project] = projectInfo;
  }

  // Schedule asychronous check against the Cloud Storage.
  var nowMillis = new Date().getTime();
  if (nowMillis - projectInfo.lastCheckedTime > checkIntervalMillis) {
    checkPassOrFail(project);
    projectInfo.lastCheckedTime = nowMillis;
  }

  var uri;
  if (projectInfo.passedFound) {
    if (projectInfo.failedFound) {
      uri = 'build-error-yellow.svg';
    } else {
      uri = 'build-passing-brightgreen.svg';
    }
  } else {
    if (projectInfo.failedFound) {
      uri = 'build-failure-brightred.svg';
    } else {
      uri = 'build-unknown-lightgrey.svg';
    }
  }
  
  res.redirect(badgeBaseUrl + uri);
};
