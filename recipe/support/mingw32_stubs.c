/* MinGW32 timezone stubs for UCRT compatibility
 *
 * The bootstrap GHC's time library references __imp__timezone and __imp__tzname
 * which are MSVCRT symbols not available in UCRT. This file provides stubs.
 *
 * In MSVCRT (old MinGW), timezone data is exported from msvcrt.dll as:
 *   - _timezone: long containing UTC offset in seconds
 *   - _tzname: array of 2 char* pointers for std/dst names
 *
 * When code is compiled with __declspec(dllimport), references become
 * __imp__timezone and __imp__tzname (pointers to the actual data).
 *
 * UCRT (modern Windows) doesn't export these - it uses _get_timezone()
 * and _get_tzname() functions instead. We provide stubs for compatibility.
 */

/* The actual timezone data */
static char _tzname_std[] = "UTC";
static char _tzname_dst[] = "UTC";

/* These are the symbols that code links against directly */
long _timezone = 0;
char *_tzname[2] = { _tzname_std, _tzname_dst };

/* These are the __imp__ pointer symbols for dllimport semantics
 * The linker looks for these when resolving __declspec(dllimport) refs */
long *__imp__timezone = &_timezone;
char **__imp__tzname = _tzname;
