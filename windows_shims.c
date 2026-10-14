/* Minimal MSVC CRT shims for cross-compiling the Windows build on Linux.
 *
 * raylib.lib for Windows is built with MSVC, so it references the /GS
 * security-cookie machinery and _fltused, which the MSVC CRT (libcmt /
 * vcruntime) normally provides but MinGW-w64 does not. Zig's bundled
 * MinGW-w64 toolchain supplies the rest of the C runtime (UCRT).
 *
 * These are only used by the cross-compile in build-windows.sh. */

#include <stdint.h>

/* Default MSVC security cookie value. */
uintptr_t __security_cookie = 0x00002B992DDFA232ULL;

/* No-op: disables /GS stack-cookie verification (safe for a trusted lib). */
void __security_check_cookie(uintptr_t cookie) { (void)cookie; }

/* Exception handler referenced by MSVC unwind info. Only invoked if an
 * exception propagates through raylib frames, which this game does not do. */
void __GSHandlerCheck(void) { }

/* MSVC range-check failure trap (from /RTC or range checks). */
void __report_rangecheckfailure(void) { __builtin_trap(); }

/* MSVC requires this symbol to be defined whenever floating point is used. */
int _fltused = 0;
