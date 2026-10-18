#include "CSwiftyTerminal.h"

#include <errno.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

void st_write_stdout(const char *text) {
    fputs(text, stdout);
    fflush(stdout);
}

void st_write_stderr(const char *text) {
    fputs(text, stderr);
    fflush(stderr);
}

void st_line_buffer_stdout(void) {
    setvbuf(stdout, NULL, _IOLBF, 0);
}

int st_isatty(int fd) {
    return isatty(fd);
}

// Expected length of a UTF-8 sequence from its lead byte; 1 for ASCII or invalid bytes.
static int st_utf8_length(unsigned char lead) {
    if (lead >= 0xF0 && lead <= 0xF4) return 4;
    if (lead >= 0xE0) return lead <= 0xEF ? 3 : 1;
    if (lead >= 0xC2) return 2;
    return 1;
}

// A byte read while checking whether Escape started a sequence but that belongs to the next
// key press (Escape, then Enter typed quickly).
static int st_pending_byte = -1;

static int st_read_byte(unsigned char *byte) {
    if (st_pending_byte >= 0) {
        *byte = (unsigned char)st_pending_byte;
        st_pending_byte = -1;
        return 1;
    }
    return read(STDIN_FILENO, byte, 1) == 1 ? 1 : 0;
}

// Serialize terminal input across StandardTerminal values. Recursive locking lets a question
// hold raw mode while individual key reads enter it again on the same thread.
static pthread_once_t st_input_once = PTHREAD_ONCE_INIT;
static pthread_mutex_t st_input_mutex;
static struct termios st_input_original;
static int st_input_depth = 0;
static volatile sig_atomic_t st_input_interrupted = 0;
static const int st_input_signals[] = {SIGINT, SIGTERM, SIGHUP};
static struct sigaction st_input_previous[3];

static void st_input_initialize(void) {
    pthread_mutexattr_t attributes;
    pthread_mutexattr_init(&attributes);
    pthread_mutexattr_settype(&attributes, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&st_input_mutex, &attributes);
    pthread_mutexattr_destroy(&attributes);
}

static void st_input_restore(void) {
    tcsetattr(STDIN_FILENO, TCSANOW, &st_input_original);
    for (size_t i = 0; i < 3; i++) {
        sigaction(st_input_signals[i], &st_input_previous[i], NULL);
    }
}

static void st_input_signalled(int signal_number) {
    int saved_errno = errno;
    st_input_interrupted = 1;
    st_input_restore();
    // Restore the host's disposition before redelivery, including custom signal handlers.
    raise(signal_number);
    errno = saved_errno;
}

static int st_input_enter(int raw) {
    pthread_once(&st_input_once, st_input_initialize);
    pthread_mutex_lock(&st_input_mutex);
    if (st_input_depth > 0) {
        if (st_input_interrupted) {
            pthread_mutex_unlock(&st_input_mutex);
            return 0;
        }
        st_input_depth++;
        return 1;
    }
    if (tcgetattr(STDIN_FILENO, &st_input_original) != 0) {
        pthread_mutex_unlock(&st_input_mutex);
        return 0;
    }
    struct termios settings = st_input_original;
    settings.c_lflag &= ~ECHO;
    if (raw) {
        settings.c_lflag &= ~(ICANON | ISIG);
        settings.c_cc[VMIN] = 1;
        settings.c_cc[VTIME] = 0;
    } else {
        settings.c_lflag |= ECHONL;
    }
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = st_input_signalled;
    sigemptyset(&action.sa_mask);
    for (size_t i = 0; i < 3; i++) {
        sigaddset(&action.sa_mask, st_input_signals[i]);
        if (sigaction(st_input_signals[i], NULL, &st_input_previous[i]) != 0) {
            pthread_mutex_unlock(&st_input_mutex);
            return 0;
        }
    }
    st_input_interrupted = 0;
    for (size_t i = 0; i < 3; i++) {
        // An ignored signal must remain ignored rather than interrupting the question.
        if (st_input_previous[i].sa_handler != SIG_IGN &&
            sigaction(st_input_signals[i], &action, NULL) != 0) {
            st_input_restore();
            pthread_mutex_unlock(&st_input_mutex);
            return 0;
        }
    }
    if (st_input_interrupted || tcsetattr(STDIN_FILENO, TCSANOW, &settings) != 0) {
        st_input_restore();
        pthread_mutex_unlock(&st_input_mutex);
        return 0;
    }
    st_input_depth = 1;
    return 1;
}

int st_raw_enter(void) {
    return st_input_enter(1);
}

void st_raw_exit(void) {
    if (st_input_depth == 0) return;
    if (--st_input_depth == 0) st_input_restore();
    pthread_mutex_unlock(&st_input_mutex);
}

int st_read_key(unsigned char *buffer, int capacity) {
    if (capacity < 1 || !st_raw_enter()) {
        return -1;
    }

    int count = st_read_byte(&buffer[0]);
    if (count == 1) {
        struct pollfd input = {.fd = STDIN_FILENO, .events = POLLIN};
        if (buffer[0] == 27) {
            // Collect the rest of a CSI/SS3 sequence; a lone Escape has nothing pending.
            unsigned char next;
            if (count < capacity && poll(&input, 1, 40) > 0 && read(STDIN_FILENO, &next, 1) == 1) {
                if (next == '[' || next == 'O') {
                    buffer[count++] = next;
                    while (count < capacity && poll(&input, 1, 40) > 0) {
                        if (read(STDIN_FILENO, &buffer[count], 1) != 1) break;
                        count++;
                        unsigned char last = buffer[count - 1];
                        if (count >= 3 && last >= 64 && last <= 126) break;
                    }
                } else {
                    st_pending_byte = next;
                }
            }
        } else {
            int expected = st_utf8_length(buffer[0]);
            while (count < expected && count < capacity && poll(&input, 1, 40) > 0) {
                if (read(STDIN_FILENO, &buffer[count], 1) != 1) break;
                count++;
            }
        }
    }

    st_raw_exit();
    return count;
}

char *st_read_secret_line_with_prompt(const char *prompt, int fd) {
    struct termios settings;
    int is_terminal = tcgetattr(STDIN_FILENO, &settings) == 0;
    int hidden = is_terminal && st_input_enter(0);
    // Never read a password with echo enabled after a terminal setup failure.
    if (is_terminal && !hidden) return NULL;

    if (prompt) {
        FILE *output = fd == STDERR_FILENO ? stderr : stdout;
        fputs(prompt, output);
        fflush(output);
    }
    char *line = NULL;
    size_t capacity = 0;
    ssize_t length = getline(&line, &capacity, stdin);
    int interrupted = hidden && st_input_interrupted;
    if (hidden) st_raw_exit();
    if (length < 0 || interrupted) {
        free(line);
        return NULL;
    }
    if (length > 0 && line[length - 1] == '\n') {
        line[--length] = '\0';
        if (length > 0 && line[length - 1] == '\r') line[--length] = '\0';
    }
    return line;
}

char *st_read_secret_line(void) {
    return st_read_secret_line_with_prompt(NULL, STDOUT_FILENO);
}

static int st_terminal_dimension(int fd, int rows) {
    const int descriptors[] = {fd, STDERR_FILENO, STDIN_FILENO, STDOUT_FILENO};
    for (size_t i = 0; i < 4; i++) {
        struct winsize size;
        if (ioctl(descriptors[i], TIOCGWINSZ, &size) == 0) {
            int value = rows ? size.ws_row : size.ws_col;
            if (value > 0) return value;
        }
    }
    return rows ? 24 : 80;
}

int st_terminal_columns_for(int fd) { return st_terminal_dimension(fd, 0); }
int st_terminal_rows_for(int fd) { return st_terminal_dimension(fd, 1); }
int st_terminal_columns(void) { return st_terminal_columns_for(STDOUT_FILENO); }
int st_terminal_rows(void) { return st_terminal_rows_for(STDOUT_FILENO); }
