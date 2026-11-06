#pragma once
#include <string>
#include <utility>
#include <vector>

// The boundary between the `https` module (the arguments, the requests in flight, the callbacks) and the
// ONE thing that differs by target: who actually talks to the network. The browser build asks fetch();
// every other build has a stub that answers "unsupported".

using HttpsHeaders = std::vector<std::pair<std::string, std::string>>;

struct HttpsRequest {
    std::string url;
    HttpsHeaders headers;
    int timeout_ms = 30000;
};

struct HttpsAnswer {
    int id = 0;
    bool sent = false;   // an answer came back (whatever its status); false: the exchange itself failed
    int status = 0;
    std::string status_text;
    std::string url;     // where the answer came from, after any redirection
    HttpsHeaders headers;
    std::string body;
    std::string error;   // why nothing came back, when sent is false
};

// `id` names the request until its answer is collected; ids are never reused.
void https_engine_start(int id, const HttpsRequest& request);

// Forgets a request: its answer, if one still comes, is dropped.
void https_engine_cancel(int id);

// Moves every answer that has arrived since the last call into `out`.
void https_engine_collect(std::vector<HttpsAnswer>& out);

// Forgets everything in flight.
void https_engine_reset();
