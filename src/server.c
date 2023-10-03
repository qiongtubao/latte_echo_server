#include "server.h"
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include "sds/sds.h"
#include "server/server.h"




/** utils  **/
/* Given the filename, return the absolute path as an SDS string, or NULL
 * if it fails for some reason. Note that "filename" may be an absolute path
 * already, this will be detected and handled correctly.
 *
 * The function does not try to normalize everything, but only the obvious
 * case of one or more "../" appearing at the start of "filename"
 * relative path. */
sds getAbsolutePath(char *filename) {
    char cwd[1024];
    sds abspath;
    sds relpath = sdsnew(filename);

    relpath = sdstrim(relpath," \r\n\t");
    if (relpath[0] == '/') return relpath; /* Path is already absolute. */

    /* If path is relative, join cwd and relative path. */
    if (getcwd(cwd,sizeof(cwd)) == NULL) {
        sdsfree(relpath);
        return NULL;
    }
    abspath = sdsnew(cwd);
    if (sdslen(abspath) && abspath[sdslen(abspath)-1] != '/')
        abspath = sdscat(abspath,"/");

    /* At this point we have the current path always ending with "/", and
     * the trimmed relative path. Try to normalize the obvious case of
     * trailing ../ elements at the start of the path.
     *
     * For every "../" we find in the filename, we remove it and also remove
     * the last element of the cwd, unless the current cwd is "/". */
    while (sdslen(relpath) >= 3 &&
           relpath[0] == '.' && relpath[1] == '.' && relpath[2] == '/')
    {
        sdsrange(relpath,3,-1);
        if (sdslen(abspath) > 1) {
            char *p = abspath + sdslen(abspath)-2;
            int trimlen = 1;

            while(*p != '/') {
                p--;
                trimlen++;
            }
            sdsrange(abspath,0,-(trimlen+1));
        }
    }

    /* Finally glue the two parts together. */
    abspath = sdscatsds(abspath,relpath);
    sdsfree(relpath);
    return abspath;
}

/** About latte RedisServer **/
int startEchoServer(struct latteEchoServer* echoServer, int argc, sds* argv) {
    echoServer->exec_argc = argc;
    echoServer->exec_argv = argv;
    //argv[0] is exec file
    echoServer->executable = getAbsolutePath(argv[0]);
    echoServer->config = createServerConfig();
    //argv[1] maybe is config file
    int attribute_index = 1;
    if (argc > 1) {
        if(argv[1][0] != '-') {
            echoServer->configfile = getAbsolutePath(argv[1]);
            if (loadConfigFromFile(echoServer->config, echoServer->configfile) == 0) {
                goto fail;
            }
            attribute_index++;
        }
    }
    //add config attribute property
    if (loadConfigFromArgv(echoServer->config, argv + attribute_index, argc - attribute_index) == 0) {
        goto fail;
    }
    echoServer->server.port = configGetLongLong(echoServer->config, "port");
    echoServer->server.bind = configGetArray(echoServer->config, "bind");
    echoServer->server.tcp_backlog = configGetLongLong(echoServer->config, "tcp-backlog");
    echoServer->server.el = aeCreateEventLoop(1024);
    initInnerLatteServer(&echoServer->server);
    echoServer->server.maxclients = 100;
    if (echoServer->server.el == NULL) {
        printf(
            "Failed creating the event loop. Error message: '%s'\n",
            strerror(errno));
        exit(1);
    }
    echoServer->server.createClient = createEchoClient;
    echoServer->server.freeClient = freeEchoClient;
    startLatteServer(&echoServer->server);
    return 1;
fail:
    printf("start latte redis fail\n");
    return 0;
}