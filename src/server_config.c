
#include "server.h"
#define DEFAULT_PORT 6379
#define DEFAULT_TCP_BACKLOG 512

config_rule_t port_rule = LL_CONFIG_INIT(DEFAULT_PORT);
config_rule_t bind_rule = SDS_ARRAY_CONFIG_INIT("* -::*");
config_rule_t tcp_backlog_rule = LL_CONFIG_INIT(DEFAULT_TCP_BACKLOG);
config_rule_t logfile_rule = SDS_CONFIG_INIT("echo.conf");

/** latte config module **/
config_manager_t* create_server_config() {
    config_manager_t* c = config_manager_new();
    sds port = sds_new_len("port", 4);
    config_register_rule(c, port, &port_rule);

    sds bind = sds_new_len("bind", 4);
    config_register_rule(c, bind, &bind_rule);
    sds tcp_backlog = sds_new_len("tcp-backlog", 11);
    config_register_rule(c, tcp_backlog, &tcp_backlog_rule);
    sds logfile = sds_new_len("logfile", 7);
    config_register_rule(c, logfile, &logfile_rule);
    return c;
}