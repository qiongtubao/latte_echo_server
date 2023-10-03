#include "ae/ae.h"
#include "connection/connection.h"
#include "sds/sds.h"
#include "server/server.h"


typedef struct client {
    struct latteClient client;
} client;

client *createEchoClient();
void freeEchoClient(client *c);
