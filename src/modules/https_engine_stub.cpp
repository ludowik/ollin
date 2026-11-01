#include "https_internal.h"

// The engine of a build with no browser: nothing can be sent, so a request is answered at once, with
// the failure the script can test for. The module still exists in full, like touch and motion, so a
// program that asks for the weather runs and shows its error instead of failing on a nil module.

namespace {
std::vector<HttpsAnswer> s_answers;
}

void https_engine_start(int id, const HttpsRequest& request) {
    HttpsAnswer a;
    a.id = id;
    a.url = request.url;
    a.error = "unsupported";
    s_answers.push_back(std::move(a));
}

void https_engine_cancel(int id) {
    for (size_t i = 0; i < s_answers.size(); i++) {
        if (s_answers[i].id == id) {
            s_answers.erase(s_answers.begin() + (long)i);
            return;
        }
    }
}

void https_engine_collect(std::vector<HttpsAnswer>& out) {
    for (auto& a : s_answers)
        out.push_back(std::move(a));
    s_answers.clear();
}

void https_engine_reset() {
    s_answers.clear();
}
