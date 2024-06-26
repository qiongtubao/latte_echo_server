
#include "server.h"
#define DEFAULT_PORT 6379
#define DEFAULT_TCP_BACKLOG 512
configRule port_rule = {
    .update = longLongUpdate,
    .writeConfigSds = longLongWriteConfigSds,
    .releaseValue = longLongReleaseValue,
    .load = longLongLoadConfig,
    .value = (void*)DEFAULT_PORT
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
    .value = (void*)DEFAULT_TCP_BACKLOG
};

configRule logfile_rule = {
    .update = sdsUpdate,
    .writeConfigSds = sdsWriteConfigSds,
    .releaseValue = sdsReleaseValue,
    .load = sdsLoadConfig,
    .value = NULL
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
    sds logfile = sdsnewlen("logfile", 7);
    registerConfig(c, logfile, &logfile_rule);
    return c;
}