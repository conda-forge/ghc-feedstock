#include <stddef.h>
typedef void* iconv_t;
extern iconv_t libiconv_open(const char*, const char*);
extern size_t libiconv(iconv_t, char**, size_t*, char**, size_t*);
extern int libiconv_close(iconv_t);

__attribute__((visibility("default")))
iconv_t iconv_open(const char* a, const char* b) { return libiconv_open(a, b); }
iconv_t _iconv_open(const char* a, const char* b) { return libiconv_open(a, b); }

__attribute__((visibility("default")))
size_t iconv(iconv_t a, char** b, size_t* c, char** d, size_t* e) { return libiconv(a,b,c,d,e); }
size_t _iconv(iconv_t a, char** b, size_t* c, char** d, size_t* e) { return libiconv(a,b,c,d,e); }

__attribute__((visibility("default")))
int iconv_close(iconv_t a) { return libiconv_close(a); }
int _iconv_close(iconv_t a) { return libiconv_close(a); }
