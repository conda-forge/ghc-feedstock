/* MinGW32 runtime initialization stubs
 * These symbols are normally provided by libmingw32.a
 * We provide minimal stubs to avoid linking the entire library
 * which contains conflicting CRT startup code (crtexewin.o)
 */

// Exception handling
void _gnu_exception_handler(void) {}
void __mingw_oldexcpt_handler(void) {}

// Runtime initialization
void __main(void) {}  // GCC runtime initialization

// TLS (Thread Local Storage) initialization
void __dyn_tls_init_callback(void) {}

// C++ static constructors/destructors arrays
void *__xc_a = 0;  // Start of C++ constructor array
void *__xc_z = 0;  // End of C++ constructor array
void *__xi_a = 0;  // Start of C++ initializer array
void *__xi_z = 0;  // End of C++ initializer array

// Native startup state (for multi-threading)
int __native_startup_state = 0;
void *__native_startup_lock = 0;

// Command line processing
int _dowildcard = 0;      // Disable wildcard expansion
int _newmode = 0;         // File open mode
int _commode = 0;         // Commit mode
int _fmode = 0;           // Default file translation mode

// Math error handling
int _matherr(void *p) { return 0; }
void __mingw_setusermatherr(void *p) {}

// Application type
int __mingw_app_type = 1;  // Console application

// TLS force initialization
int __mingw_initltssuo_force = 0;
int __mingw_initltsdyn_force = 0;
int __mingw_initltsdrot_force = 0;

// Runtime relocator (for DLL support)
void _pei386_runtime_relocator(void) {}

// Command line arguments
void _setargv(void) {}
