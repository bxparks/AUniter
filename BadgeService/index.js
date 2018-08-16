/**
 * Copyright 2018 Brian T. Park
 *
 * MIT License
 *
 * A Google Functions microservice which returns a shields.io badge depending
 * on the status of the Jenkins continuous integration of a given project.
 *
 * The GET handler is at:
 *  - https://us-central1-xparks2018.cloudfunctions.net/badge?project={project}
 * The {project} is the name of the project being queried.
 *
 * It looks for a status file in Google Cloud Storage, in the given
 * 'bucketName', with the form:
 *
 *  - '{project}=PASSED'
 *  - '{project}=FAILED'
 *
 * There are 5 possible badges:
 *
 *  - If the PASSED file is detected, then a "passing" badge from shields.io is
 *    returned.
 *  - If the FAILED file is detected, a "failure" badge from shields.io is
 *    returned.
 *  - If both of these marker files are miising, then an "unknown" badge is
 *    returned.
 *  - If both of these markers file exist (which shouldn't happen), then
 *    an "error" badge is returned.
 *  - If {project} is not given, then an "invalid" badge is returned.
 *
 * Deployment:
 *
 *  $ gcloud functions deploy badge --trigger-http
 */

'use strict';

// The Google Cloud Storage bucket name used to hold the continuous integration
// (CI) test results. NOTE: Change this to your own bucket.
const bucketName = 'xparks-jenkins';

// Number of milliseconds between successive calls to checkPassOrFail().
const checkIntervalMillis = 1 * 60 * 1000;

// Cache of static badges from https://img.shields.io/badge/
const badges = {
  'build-passing-brightgreen.svg':
      '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="88" height="20"><linearGradient id="b" x2="0" y2="100%"><stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient><clipPath id="a"><rect width="88" height="20" rx="3" fill="#fff"/></clipPath><g clip-path="url(#a)"><path fill="#555" d="M0 0h37v20H0z"/><path fill="#4c1" d="M37 0h51v20H37z"/><path fill="url(#b)" d="M0 0h88v20H0z"/></g><g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="110"> <text x="195" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="270">build</text><text x="195" y="140" transform="scale(.1)" textLength="270">build</text><text x="615" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="410">passing</text><text x="615" y="140" transform="scale(.1)" textLength="410">passing</text></g> </svg>',
  'build-failure-red.svg':
      '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="82" height="20"><linearGradient id="b" x2="0" y2="100%"><stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient><clipPath id="a"><rect width="82" height="20" rx="3" fill="#fff"/></clipPath><g clip-path="url(#a)"><path fill="#555" d="M0 0h37v20H0z"/><path fill="#e05d44" d="M37 0h45v20H37z"/><path fill="url(#b)" d="M0 0h82v20H0z"/></g><g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="110"> <text x="195" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="270">build</text><text x="195" y="140" transform="scale(.1)" textLength="270">build</text><text x="585" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="350">failure</text><text x="585" y="140" transform="scale(.1)" textLength="350">failure</text></g> </svg>',
  'build-invalid-orange.svg':
      '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="82" height="20"><linearGradient id="b" x2="0" y2="100%"><stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient><clipPath id="a"><rect width="82" height="20" rx="3" fill="#fff"/></clipPath><g clip-path="url(#a)"><path fill="#555" d="M0 0h37v20H0z"/><path fill="#fe7d37" d="M37 0h45v20H37z"/><path fill="url(#b)" d="M0 0h82v20H0z"/></g><g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="110"> <text x="195" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="270">build</text><text x="195" y="140" transform="scale(.1)" textLength="270">build</text><text x="585" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="350">invalid</text><text x="585" y="140" transform="scale(.1)" textLength="350">invalid</text></g> </svg>',
  'build-error-yellow.svg':
      '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="74" height="20"><linearGradient id="b" x2="0" y2="100%"><stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient><clipPath id="a"><rect width="74" height="20" rx="3" fill="#fff"/></clipPath><g clip-path="url(#a)"><path fill="#555" d="M0 0h37v20H0z"/><path fill="#dfb317" d="M37 0h37v20H37z"/><path fill="url(#b)" d="M0 0h74v20H0z"/></g><g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="110"> <text x="195" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="270">build</text><text x="195" y="140" transform="scale(.1)" textLength="270">build</text><text x="545" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="270">error</text><text x="545" y="140" transform="scale(.1)" textLength="270">error</text></g> </svg>',
  'build-unknown-lightgrey.svg':
      '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="98" height="20"><linearGradient id="b" x2="0" y2="100%"><stop offset="0" stop-color="#bbb" stop-opacity=".1"/><stop offset="1" stop-opacity=".1"/></linearGradient><clipPath id="a"><rect width="98" height="20" rx="3" fill="#fff"/></clipPath><g clip-path="url(#a)"><path fill="#555" d="M0 0h37v20H0z"/><path fill="#9f9f9f" d="M37 0h61v20H37z"/><path fill="url(#b)" d="M0 0h98v20H0z"/></g><g fill="#fff" text-anchor="middle" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="110"> <text x="195" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="270">build</text><text x="195" y="140" transform="scale(.1)" textLength="270">build</text><text x="665" y="150" fill="#010101" fill-opacity=".3" transform="scale(.1)" textLength="510">unknown</text><text x="665" y="140" transform="scale(.1)" textLength="510">unknown</text></g> </svg>',
};

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
function getBadgeForProject(project) {
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
        return 'build-failure-red.svg';
      } else {
        return 'build-unknown-lightgrey.svg';
      }
    }
  }
}

/** Send the image corresponding to 'badge'. */
function sendBadgeImage(res, badge) {
  const badgeImage = badges[badge];
  res.type('image/svg+xml;charset=utf-8');
  res.header('Cache-Control', 'no-cache, no-store, must-revalidate');
  res.send(badgeImage);
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
  if (!project) {
    sendBadgeImage(res, 'build-invalid-orange.svg');
    return;
  }
  console.log('badge(): Processing project: ', project);

  // Use the cache if it was updated recently.
  const nowMillis = new Date().getTime();
  if (nowMillis - lastCheckedTime <= checkIntervalMillis) {
    sendBadgeImage(res, getBadgeForProject(project));
    return;
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
        sendBadgeImage(res, getBadgeForProject(project));
      })
      .catch(err => {
        console.error('ERROR: ', err);
        res.status(500).end();
      });
};
