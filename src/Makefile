
LIB_MODUELS="sds dict ae config connection list endianconv rax server log"

uname_S:= $(shell sh -c 'uname -s 2>/dev/null || echo not')
uname_M:= $(shell sh -c 'uname -s 2>/dev/null || echo not')

OPTIMIZATION?=-O0
STD=-std=c99 -pedantic -DREDIS_STATIC=''
WARN=-Wall -W -Wno-missing-field-initializers
OPT=$(OPTIMIZATION)
DEBUG=-g -ggdb
FINAL_CFLAGS=$(STD) $(WARN) $(OPT) $(DEBUG) $(CFLAGS) $(LATTE_REDIS_CFLAGS)
LATTE_REDIS_CC=$(QUIET_CC)$(CC) $(FINAL_CFLAGS)
ifeq ($(uname_S),Linux)
	FINAL_SHARD_LIB=-lrt 
endif

LATTE_LIBS:= ../deps/latte_c/out/lib/liblatte.a 
latte_lib:
	cd ../deps/latte_c && make build MODULES=$(LIB_MODUELS) 

%.o: %.c 
	$(LATTE_REDIS_CC) -o $@ -c $< -I../deps/latte_c/out/include 

MAC_M1_CFLAGS=-fprofile-arcs -ftest-coverage
OBJS= main.o server.o  server_config.o client.o
# -lstdc++
all: latte_lib $(OBJS) 
	$(LATTE_REDIS_CC) -o main $(OBJS) -I../deps/latte_c/out/include $(LATTE_LIBS)  $(FINAL_SHARD_LIB) -lm  -ldl -lz -lstdc++ -lpthread $(MAC_M1_CFLAGS)
	

clean:
	cd ../deps/latte_c && make clean_all 
	rm -rf *.o 
	rm -rf main

test: 
	@(cd ..; ./runtest )