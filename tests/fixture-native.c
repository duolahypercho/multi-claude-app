/* A disposable native process that records startup without opening Claude. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void field(const char *value) {
    if (!value) value = "";
    fwrite(value, 1, strlen(value) + 1, stdout);
}
int main(int argc, char **argv) {
    char pid[32]; snprintf(pid, sizeof(pid), "%d", getpid()); field(pid);
    for (int i = 0; i < argc; i++) field(argv[i]);
    field(getenv("CLAUDE_CONFIG_DIR")); field(getenv("CLAUDE_USER_DATA_DIR"));
    field(getenv("CLAUDE_CDP_AUTH")); field(getenv("ELECTRON_RUN_AS_NODE"));
    field(getenv("DISABLE_AUTOUPDATER"));
    return 0;
}
