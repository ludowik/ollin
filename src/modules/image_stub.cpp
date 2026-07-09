#include "image_module.h"

Value makeImageModule() {
    return Value();
}
void image_preload(const std::string&, const std::vector<uint8_t>&, const std::string&) {
}
void image_preload_b64(const std::string&, const std::string&, const std::string&) {
}
void image_reset() {
}
void image_draw_sprite(int, float, float, float, float, unsigned char, unsigned char, unsigned char, unsigned char) {
}
void image_set_tint(bool, unsigned char, unsigned char, unsigned char, unsigned char) {
}
void image_get_tint(bool* has, unsigned char* r, unsigned char* g, unsigned char* b, unsigned char* a) {
    *has = false; // paramètres de sortie initialisés : pas de teinte (blanc)
    *r = *g = *b = *a = 255;
}
