#pragma once
#include <stddef.h>

/// Writes `text` to stdout through the C stdio buffer and flushes it, so library output stays
/// ordered with the host program's `print` calls.
void st_write_stdout(const char *text);

/// Writes `text` to stderr and flushes it.
void st_write_stderr(const char *text);

/// Line-buffers stdout. Swift 6's strict concurrency checking flags a direct
/// `setvbuf(stdout, ...)` from Swift as touching non-Sendable global state on Linux (Glibc's
/// `stdout` isn't annotated the way Darwin's is); doing it in C sidesteps that entirely.
void st_line_buffer_stdout(void);

/// Whether the file descriptor is a terminal.
int st_isatty(int fd);

/// Puts stdin in raw mode (no echo, no line buffering, no signals) until the matching
/// `st_raw_exit`. Calls nest. While raw mode is held, SIGINT, SIGTERM and SIGHUP restore the terminal
/// before their previous disposition runs.
///
/// - Returns: 1 when stdin is a terminal now in raw mode, 0 otherwise.
int st_raw_enter(void);

/// Ends one `st_raw_enter`; the outermost call restores the saved terminal settings.
void st_raw_exit(void);

/// Reads one key press from stdin in raw mode (no echo, no line buffering, no signals) and
/// restores the terminal before returning. An escape sequence (arrows, function keys) or a
/// multi-byte UTF-8 character is returned whole. Inside `st_raw_enter`/`st_raw_exit` the
/// terminal stays raw between reads, so keys typed while output is drawn are not echoed.
///
/// - Returns: the number of bytes written to `buffer` (at least 1), 0 at end of input, or -1
///   when stdin is not a terminal.
int st_read_key(unsigned char *buffer, int capacity);

/// Reads one line from stdin with echo disabled, for passwords and keys. SIGINT, SIGTERM and SIGHUP
/// restore echo before the previous signal disposition runs.
///
/// - Returns: a heap-allocated, newline-stripped string the caller must free(), or NULL at
///   end of input.
char *st_read_secret_line(void);

/// Current terminal width in columns; 80 when it cannot be determined.
int st_terminal_columns(void);

/// Current terminal height in rows; 24 when it cannot be determined.
int st_terminal_rows(void);

/// Width of the terminal attached to fd, falling back to other standard streams, then 80.
int st_terminal_columns_for(int fd);

/// Height of the terminal attached to fd, falling back to other standard streams, then 24.
int st_terminal_rows_for(int fd);

/// Disables echo before writing prompt to fd (stdout or stderr), then reads a secret line.
/// The result is allocated like st_read_secret_line and must be freed by the caller.
char *st_read_secret_line_with_prompt(const char *prompt, int fd);
