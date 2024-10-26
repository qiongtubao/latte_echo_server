#include "server.h"
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include "sds/sds.h"
#include "server/server.h"
#include <time.h>
#include <sys/time.h>
#include "log/log.h"
/* Log levels */
// #define LL_DEBUG 0
// #define LL_VERBOSE 1
// #define LL_NOTICE 2
// #define LL_WARNING 3
// #define LL_RAW (1<<10) /* Modifier to log without timestamp */

/* Return the UNIX time in microseconds */
// long long ustime(void) {
//     struct timeval tv;
//     long long ust;

//     gettimeofday(&tv, NULL);
//     ust = ((long long)tv.tv_sec)*1000000;
//     ust += tv.tv_usec;
//     return ust;
// }
// long getDaylightActive() {
//     struct tm tm;
//     time_t ut = ustime() / 1000000;
//     localtime_r(&ut,&tm);
//     return tm.tm_isdst;
// }
/*
 * priorities/facilities are encoded into a single 32-bit quantity, where the
 * bottom 3 bits are the priority (0-7) and the top 28 bits are the facility
 * (0-big number).  Both the priorities and the facilities map roughly
 * one-to-one to strings in the syslogd(8) source code.  This mapping is
 * included in this file.
 *
 * priorities (these are ordered)
 */
// #define LOG_EMERG       0       /* system is unusable */
// #define LOG_ALERT       1       /* action must be taken immediately */
// #define LOG_CRIT        2       /* critical conditions */
// #define LOG_ERR         3       /* error conditions */
// #define LOG_WARNING     4       /* warning conditions */
// #define LOG_NOTICE      5       /* normal but significant condition */
// #define LOG_INFO        6       /* informational */
// #define LOG_DEBUG       7       /* debug-level messages */


/*
 * Gets the proper timezone in a more portable fashion
 * i.e timezone variables are linux specific.
 */
// long getTimeZone(void) {
// #if defined(__linux__) || defined(__sun)
//     return timezone;
// #else
//     struct timeval tv;
//     struct timezone tz;

//     gettimeofday(&tv, &tz);

//     return tz.tz_minuteswest * 60L;
// #endif
// }

/* This is a safe version of localtime() which contains no locks and is
 * fork() friendly. Even the _r version of localtime() cannot be used safely
 * in Redis. Another thread may be calling localtime() while the main thread
 * forks(). Later when the child process calls localtime() again, for instance
 * in order to log something to the Redis log, it may deadlock: in the copy
 * of the address space of the forked process the lock will never be released.
 *
 * This function takes the timezone 'tz' as argument, and the 'dst' flag is
 * used to check if daylight saving time is currently in effect. The caller
 * of this function should obtain such information calling tzset() ASAP in the
 * main() function to obtain the timezone offset from the 'timezone' global
 * variable. To obtain the daylight information, if it is currently active or not,
 * one trick is to call localtime() in main() ASAP as well, and get the
 * information from the tm_isdst field of the tm structure. However the daylight
 * time may switch in the future for long running processes, so this information
 * should be refreshed at safe times.
 *
 * Note that this function does not work for dates < 1/1/1970, it is solely
 * designed to work with what time(NULL) may return, and to support Redis
 * logging of the dates, it's not really a complete implementation. */
static int is_leap_year(time_t year) {
    if (year % 4) return 0;         /* A year not divisible by 4 is not leap. */
    else if (year % 100) return 1;  /* If div by 4 and not 100 is surely leap. */
    else if (year % 400) return 0;  /* If div by 100 *and* not by 400 is not leap. */
    else return 1;                  /* If div by 100 and 400 is leap. */
}

void nolocks_localtime(struct tm *tmp, time_t t, time_t tz, int dst) {
    const time_t secs_min = 60;
    const time_t secs_hour = 3600;
    const time_t secs_day = 3600*24;

    t -= tz;                            /* Adjust for timezone. */
    t += 3600*dst;                      /* Adjust for daylight time. */
    time_t days = t / secs_day;         /* Days passed since epoch. */
    time_t seconds = t % secs_day;      /* Remaining seconds. */

    tmp->tm_isdst = dst;
    tmp->tm_hour = seconds / secs_hour;
    tmp->tm_min = (seconds % secs_hour) / secs_min;
    tmp->tm_sec = (seconds % secs_hour) % secs_min;

    /* 1/1/1970 was a Thursday, that is, day 4 from the POV of the tm structure
     * where sunday = 0, so to calculate the day of the week we have to add 4
     * and take the modulo by 7. */
    tmp->tm_wday = (days+4)%7;

    /* Calculate the current year. */
    tmp->tm_year = 1970;
    while(1) {
        /* Leap years have one day more. */
        time_t days_this_year = 365 + is_leap_year(tmp->tm_year);
        if (days_this_year > days) break;
        days -= days_this_year;
        tmp->tm_year++;
    }
    tmp->tm_yday = days;  /* Number of day of the current year. */

    /* We need to calculate in which month and day of the month we are. To do
     * so we need to skip days according to how many days there are in each
     * month, and adjust for the leap year that has one more day in February. */
    int mdays[12] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
    mdays[1] += is_leap_year(tmp->tm_year);

    tmp->tm_mon = 0;
    while(days >= mdays[tmp->tm_mon]) {
        days -= mdays[tmp->tm_mon];
        tmp->tm_mon++;
    }

    tmp->tm_mday = days+1;  /* Add 1 since our 'days' is zero-based. */
    tmp->tm_year -= 1900;   /* Surprisingly tm_year is year-1900. */
}
/* Low level logging. To use only for very big messages, otherwise
 * serverLog() is to prefer. */
// void serverLogRaw(int level, const char *msg) {
//     const int syslogLevelMap[] = { LOG_DEBUG, LOG_INFO, LOG_NOTICE, LOG_WARNING };
//     const char *c = ".-*#";
//     FILE *fp;
//     char buf[64];
//     // int rawmode = (level & LL_RAW);
//     int rawmode = 0;
//     // int log_to_stdout = server.logfile[0] == '\0';

//     level &= 0xff; /* clear flags */
//     // if (level < server.verbosity) return;

//     // fp = log_to_stdout ? stdout : fopen(server.logfile,"a");
//     fp = stdout;
//     if (!fp) return;

//     if (rawmode) {
//         fprintf(fp,"%s",msg);
//     } else {
//         int off;
//         struct timeval tv;
//         int role_char;
//         pid_t pid = getpid();

//         gettimeofday(&tv,NULL);
//         struct tm tm;
//         nolocks_localtime(&tm,tv.tv_sec,getTimeZone(),getDaylightActive());
//         off = strftime(buf,sizeof(buf),"%d %b %Y %H:%M:%S.",&tm);
//         snprintf(buf+off,sizeof(buf)-off,"%03d",(int)tv.tv_usec/1000);
//         // if (pid != server.pid) {
//         //     role_char = 'C'; /* RDB / AOF writing child. */
//         // } else {
//         //     role_char = (server.masterhost ? 'S':'M'); /* Slave or Master. */
//         // }
//         role_char = 'C';
//         fprintf(fp,"%d:%c %s %c %s\n",
//             (int)getpid(),role_char, buf,c[level],msg);
//     }
//     fflush(fp);

//     // if (!log_to_stdout) fclose(fp);
//     // if (server.syslog_enabled) syslog(syslogLevelMap[level], "%s", msg);
// }

// #define LOG_MAX_LEN    1024 /* Default maximum length of syslog messages.*/

// /* Like serverLogRaw() but with printf-alike support. This is the function that
//  * is used across the code. The raw version is only used in order to dump
//  * the INFO output on crash. */
// void _serverLog(int level, const char *fmt, ...) {
//     va_list ap;
//     char msg[LOG_MAX_LEN];

//     va_start(ap, fmt);
//     vsnprintf(msg, sizeof(msg), fmt, ap);
//     va_end(ap);

//     serverLogRaw(level,msg);
// }
// /* Use macro for checking log level to avoid evaluating arguments in cases log
//  * should be ignored due to low level. */
// #define serverLog(level, ...) do {\
//         _serverLog(level, __VA_ARGS__);\
//     } while(0)


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
    sds relpath = sds_new(filename);

    relpath = sds_trim(relpath," \r\n\t");
    if (relpath[0] == '/') return relpath; /* Path is already absolute. */

    /* If path is relative, join cwd and relative path. */
    if (getcwd(cwd,sizeof(cwd)) == NULL) {
        sds_delete(relpath);
        return NULL;
    }
    abspath = sds_new(cwd);
    if (sds_len(abspath) && abspath[sds_len(abspath)-1] != '/')
        abspath = sds_cat(abspath,"/");

    /* At this point we have the current path always ending with "/", and
     * the trimmed relative path. Try to normalize the obvious case of
     * trailing ../ elements at the start of the path.
     *
     * For every "../" we find in the filename, we remove it and also remove
     * the last element of the cwd, unless the current cwd is "/". */
    while (sds_len(relpath) >= 3 &&
           relpath[0] == '.' && relpath[1] == '.' && relpath[2] == '/')
    {
        sds_range(relpath,3,-1);
        if (sds_len(abspath) > 1) {
            char *p = abspath + sds_len(abspath)-2;
            int trimlen = 1;

            while(*p != '/') {
                p--;
                trimlen++;
            }
            sds_range(abspath,0,-(trimlen+1));
        }
    }

    /* Finally glue the two parts together. */
    abspath = sds_cat_sds(abspath,relpath);
    sds_delete(relpath);
    return abspath;
}

/** About latte RedisServer **/
int startEchoServer(struct latteEchoServer* echoServer, int argc, sds* argv) {
    echoServer->exec_argc = argc;
    echoServer->exec_argv = argv;
    //argv[0] is exec file
    echoServer->executable = getAbsolutePath(argv[0]);
    echoServer->config = create_server_config();
    //argv[1] maybe is config file
    int attribute_index = 1;
    if (argc > 1) {
        if(argv[1][0] != '-') {
            echoServer->configfile = getAbsolutePath(argv[1]);
            if (load_config_from_file(echoServer->config, echoServer->configfile) == 0) {
                goto fail;
            }
            attribute_index++;
        }
    }
    //add config attribute property
    if (load_config_from_argv(echoServer->config, argv + attribute_index, argc - attribute_index) == 0) {
        goto fail;
    }

    sds file = config_get_sds(echoServer->config, "logfile");
    if (file == NULL) {
        log_add_stdout("latte_c", LOG_DEBUG);
        log_add_stdout(LATTE_ECHO_SERVER_LOG_TAG, LOG_DEBUG);
    } else {
        log_add_file("latte_c", file, LOG_INFO);
        log_add_file(LATTE_ECHO_SERVER_LOG_TAG, file, LOG_INFO);
    }
    echoServer->server.port = config_get_int64(echoServer->config, "port");
    echoServer->server.bind = config_get_array(echoServer->config, "bind");
    echoServer->server.tcp_backlog = config_get_int64(echoServer->config, "tcp-backlog");
    echoServer->server.el = aeCreateEventLoop(1024);
    
    initInnerLatteServer(&echoServer->server);
    echoServer->server.maxclients = 100;
    if (echoServer->server.el == NULL) {
        echoServerLog(LOG_ERROR,
            "Failed creating the event loop. Error message: '%s'",
            strerror(errno));
        exit(1);
    }
    echoServer->server.createClient = createEchoClient;
    echoServer->server.freeClient = freeEchoClient;
    startLatteServer(&echoServer->server);
    return 1;
fail:
    echoServerLog(LOG_DEBUG, "start latte server fail");
    return 0;
}
