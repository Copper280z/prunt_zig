#include "host_time.h"
#include "sync_protocol.h"
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// transport_*.c
int transport_init(uint16_t vid, uint16_t pid);
void transport_close(void);
int transport_send(const void *buf, int len);
int transport_recv(void *buf, int len, int timeout_ms);

static volatile int g_running = 1;

static void sigint_handler(int sig) {
  (void)sig;
  g_running = 0;
}

int main(int argc, char **argv) {
  uint16_t vid = 0xCafe; // adjust to match your descriptor
  uint16_t pid = 0x4011;

  if (transport_init(vid, pid) != 0) {
    return 1;
  }

  signal(SIGINT, sigint_handler);

  {
    sync_hello_t hello;
    hello.msg_type = SYNC_MSG_TYPE_HELLO;
    hello.reserved = 0;
    hello.reserved2 = 0;
    hello.protocol_version = 1;

    transport_send(&hello, sizeof(hello));
    zero_clock();
  }

  FILE *log = fopen("sync_log.csv", "w");
  if (!log) {
    perror("fopen");
    transport_close();
    return 1;
  }

  fprintf(log, "host_time_ns,seq,offset_ns,delay_ns,freq_corr_ppm\n");
  fflush(log);

  uint8_t buf[64];

  while (g_running) {
    int n = transport_recv(buf, sizeof(buf), 100); // 100 ms timeout
    if (n < 0) {
      break; // error
    }
    if (n == 0) {
      printf("No data\n");
      // no data
      continue;
    }
    printf("Got Data!\n");

    uint8_t msg_type = buf[0];
    if (msg_type == SYNC_MSG_TYPE_REQ && n == sizeof(sync_req_t)) {
      // Device -> host sync request
      sync_req_t req;
      memcpy(&req, buf, sizeof(req));

      uint64_t t1 = host_time_now_ns();

      sync_resp_t resp;
      memset(&resp, 0, sizeof(resp));
      resp.msg_type = SYNC_MSG_TYPE_RESP;
      resp.reserved = 0;
      resp.seq = req.seq;
      resp.t1_ns = t1;
      resp.t2_ns = host_time_now_ns(); // just before send

      transport_send(&resp, sizeof(resp));
    } else if (msg_type == SYNC_MSG_TYPE_STATS && n == sizeof(sync_stats_t)) {

      sync_stats_t stats;
      memcpy(&stats, buf, sizeof(stats));

      uint64_t host_now = host_time_now_ns();

      fprintf(log, "%llu,%u,%lld,%lld,%d\n", (unsigned long long)host_now,
              (unsigned)stats.seq, (long long)stats.offset_ns,
              (long long)stats.delay_ns, (int)stats.freq_corr_ppm);
      fflush(log);
    } else {
      // ignore unknown message
    }
  }

  fclose(log);
  transport_close();
  return 0;
}
