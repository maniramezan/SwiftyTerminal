#pragma once
#include <stdlib.h>

/// Displays `prompt`, reads a line with full terminal editing (arrow keys,
/// history, Ctrl-A/E/K/U/W, Alt-Backspace, etc.) via libedit.
///
/// - Returns a heap-allocated C string the caller must free(), or NULL on EOF.
/// - Non-empty lines are automatically added to the in-session history.
char *st_le_readline(const char *prompt);

/// Persist the current history to `path` (creates/truncates the file).
void st_le_save_history(const char *path);

/// Load history from `path` into the current session.
void st_le_load_history(const char *path);

/// Clear all configured completion entries.
void st_le_reset_completions(void);

/// Configure root-level completions (newline-delimited command list).
void st_le_set_root_completions(const char *items);

/// Configure argument completions for a command (newline-delimited values).
void st_le_set_command_completions(const char *command, const char *items);

/// Returns non-zero when `candidate` should match `text` for completion.
/// Prefix matches win; substring matches are only accepted when prefix mode is disabled.
int st_le_completion_candidate_matches(const char *candidate, const char *text, int prefer_prefix);

