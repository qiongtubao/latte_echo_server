
#include "server.h"
#define DEFAULT_PORT 6379
#define DEFAULT_TCP_BACKLOG 512
configRule port_rule = {
    .update = longLongUpdate,
    .writeConfigSds = longLongWriteConfigSds,
    .releaseValue = longLongReleaseValue,
    .load = longLongLoadConfig,
    .value = DEFAULT_PORT
};


configRule bind_rule = {
    .update = arraySdsUpdate,
    .writeConfigSds = arraySdsWriteConfigSds,
    .releaseValue = arraySdsReleaseValue,
    .load = arraySdsLoadConfig
};

configRule tcp_backlog_rule = {
    .update = longLongUpdate,
    .writeConfigSds = longLongWriteConfigSds,
    .releaseValue = longLongReleaseValue,
    .load = longLongLoadConfig,
    .value = DEFAULT_TCP_BACKLOG
};

/** latte config module **/
config* createServerConfig() {
    config* c = createConfig();
    sds port = sdsnewlen("port", 4);
    registerConfig(c, port, &port_rule);

    sds bind = sdsnewlen("bind", 4);
    registerConfig(c, bind, &bind_rule);
    sds tcp_backlog = sdsnewlen("tcp-backlog", 11);
    registerConfig(c, tcp_backlog, &tcp_backlog_rule);
    return c;
}