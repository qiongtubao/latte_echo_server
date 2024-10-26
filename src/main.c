#include "main.h"


#include <string.h>

struct latteEchoServer echoServer;


sds* parseArgv(int argc, char** argv, int* len) {
    char** result = zmalloc(sizeof(sds)*(argc + 1));
    result[argc] = NULL;
    for(int j = 0; j < argc; j++) {
        result[j] = sds_new_len(argv[j], strlen(argv[j]));
    }
    *len = argc;
    return result;
}


int main(int argc, char **argv) {
    int exec_argc;
    log_init();
    sds* exec_argv = parseArgv(argc, argv, &exec_argc);
    startEchoServer(&echoServer, exec_argc, exec_argv);

end:
    for(int i = 0; i < exec_argc; i++) {
        sds_delete(exec_argv[i]);
    }
    zfree(exec_argv);
    return 1;
}