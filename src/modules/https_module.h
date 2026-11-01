#pragma once
#include "value.h"

// The `https` module: asks a server for something over HTTPS, and hands the answer to a function
// of the script when it comes.
//
//   https.get(url [, options], callback)   returns a request; callback(response) runs LATER, once
//   https.urlEncode(text)                   `text` written to travel inside an address
//   https.query(url, fields)                `url` followed by the fields of a map as ?name=value&…
//   https.update()                          delivers the answers by hand, for a program with no render loop
//
//   options   {headers: {name: value, …}, timeout: seconds}      30 seconds by default
//   response  {ok, status, statusText, headers, body, error, url}
//             ok is true for a status from 200 to 299; a server's refusal (404…) is an answer, with its
//             status and body, and `error` is nil. When nothing came back at all (no network, a refused
//             connection, the time limit, a server that does not allow this page to read it) status is 0,
//             body is "" and `error` says why.
//   request   req.cancel() — the callback will not run;  req.done() — answered or cancelled
//
// Only https:// addresses are accepted: a page served over HTTPS may not ask for anything else, and an
// unencrypted exchange is not one this module offers. Mistakes in the call (a wrong address, a wrong type,
// too many requests at once) are errors raised at once; a failure of the exchange arrives in the response.
//
// Everything is done by the browser (fetch): the module is therefore subject to its rules, among them that a
// server must allow the page to read its answer (CORS). Outside the browser the module exists in full and
// every request fails with the error "unsupported".
Value make_https_module();

// Delivers the answers that have come in. Called once a frame by the render loop, before update().
void https_poll();

// When a program starts: drops what the previous one asked for, so that no answer reaches the wrong program.
void https_reset();
