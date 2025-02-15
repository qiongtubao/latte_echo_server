#include "client.h" 
#include <stdio.h>
#include "utils/atomic.h"
#include "zmalloc/zmalloc.h"
#include <string.h>
#include "server.h"


int echoHandler(struct latteClient* lc) {
    struct client* c = (struct client*)lc; 
    lc->qb_pos = sds_len(lc->querybuf);
    if (connWrite(lc->conn, lc->querybuf, lc->qb_pos) == -1) {
        echoServerLog(LOG_DEBUG,"write fail");
    }
    return 1;
}
latteClient *createEchoClient() {
    client* c = zmalloc(sizeof(client));
    c->client.exec = echoHandler;
    return c;
}

void freeEchoClient(latteClient* c) {
    zfree(c);
}
