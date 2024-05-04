#ifndef __LATTE_ECHO_CLIENT_H
#define __LATTE_ECHO_CLIENT_H
#include "ae/ae.h"
#include "connection/connection.h"
#include "sds/sds.h"
#include "server/server.h"


typedef struct client {
    struct latteClient client;
} client;

latteClient *createEchoClient();
void freeEchoClient(latteClient *c);
#endif
