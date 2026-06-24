#include "image_module.h"

Value makeImageModule()    { return Value(); }
void  image_preload(const std::string&, const std::vector<uint8_t>&, const std::string&) {}
void  image_preload_b64(const std::string&, const std::string&, const std::string&)      {}
void  image_reset()        {}
