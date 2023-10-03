#ifndef __LATTE_ECHO_SERVER_H
#define __LATTE_ECHO_SERVER_H
#include "dict/dict.h"
#include "ae/ae.h"
#include "anet/anet.h"
#include <pthread.h>
#include "sds/sds.h"
#include "config/config.h"
#include "client.h"
#include "list/list.h"
#include "endianconv/endianconv.h"
#include "rax/rax.h"
#include "server/server.h"


/* Error codes */
#define SERVER_OK                    0
#define SERVER_ERR                   -1

#define CONFIG_BINDADDR_MAX 16
// typedef struct socketFds {
//     int fd[CONFIG_BINDADDR_MAX];
//     int count;
// } socketFds;
#define ANET_ERR_LEN 256

typedef void *(*tcpHandlerFunc)(aeEventLoop *el, int fd, void *privdata, int mask);


/* Global vars */
struct latteEchoServer server; /* Server global state */
config* createServerConfig();

/** latte redis server **/
typedef struct latteEchoServer {
    struct latteServer server;
    int exec_argc;
    sds* exec_argv;
    sds executable; /** execut file path **/
    sds configfile;
    struct config* config;
} latteEchoServer;


/**
 * @brief 
 * 
 * @param echoServer 
 * @param argc 
 * @param argv 
 * @return int 
 *      启动echoServer 通过参数方式
 *      包含  init echoServer
 *      
 */
#define PRIVATE 

PRIVATE int startEchoServer(struct latteEchoServer* redisServer, int argc, sds* argv);

#endif