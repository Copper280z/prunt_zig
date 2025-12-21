#include "node_time.h"
#include "sched_servo.h"
#include "sync_protocol.h"
#include "tusb.h"
#include "vendor/vendor_device.h"
#include <stdio.h>
#include <string.h>

extern sched_servo_fixed_t g_sched_servo;

// Only one outstanding request at a time
static sync_req_t g_last_req;
static int g_req_pending = 0;
static uint16_t g_seq = 0;
static uint8_t g_host_ready = 0;

// Sync interval (e.g. every 20 ms)
#define SYNC_INTERVAL_TICKS 20 // if scheduler tick is 1 ms

static uint32_t g_sync_tick_counter = 0;
extern uint64_t scheduler_time_ns;

void sync_init(void) {
  memset(&g_last_req, 0, sizeof(g_last_req));
  g_req_pending = 0;
  g_seq = 0;
  g_sync_tick_counter = 0;
  g_host_ready = 0;
}

// Called from scheduler_tick_handler() once per 1 ms tick
void sync_tick(void) {
  g_sync_tick_counter++;

  if (!g_req_pending && g_sync_tick_counter >= SYNC_INTERVAL_TICKS) {
    g_sync_tick_counter = 0;
    if (!g_host_ready)
      return;

    sync_req_t req;
    req.msg_type = SYNC_MSG_TYPE_REQ;
    req.reserved = 0;
    req.seq = ++g_seq;
    // req.t0_ns = node_time_now_ns();
    zero_clock();
    req.t0_ns = scheduler_time_ns;

    // Save last req
    g_last_req = req;
    g_req_pending = 1;

    // Send it
    tud_vendor_write(&req, sizeof(req));
    tud_vendor_write_flush();

    // uint32_t bytes_sent = tud_vendor_flush();
    printf("Sent sync request\n");
    // printf("sent %u bytes\n", bytes_sent);
  } else if (g_req_pending && g_sync_tick_counter >= SYNC_INTERVAL_TICKS) {
    // g_host_ready = 0;
    // g_sync_tick_counter = 0;
    // printf("Host timed out\n");
  }
}

// Called when we receive a SYNC_RESP from host
static void handle_sync_resp(const sync_resp_t *resp) {
  if (!g_req_pending) {
    return;
  }

  if (resp->seq != g_last_req.seq) {
    // stale or mismatched; ignore
    return;
  }

  uint64_t t3_node_ns =
      g_last_req.t0_ns +
      ((int32_t)(g_sched_servo.freq_corr_fp * node_time_now_ns()) >>
       SERVO_FP_SHIFT);

  sched_servo_fixed_on_sync(&g_sched_servo, g_last_req.t0_ns, resp->t1_ns,
                            resp->t2_ns, t3_node_ns);

  g_req_pending = 0;

  // After updating servo, send stats to host
  sync_stats_t stats;
  stats.msg_type = SYNC_MSG_TYPE_STATS;
  stats.reserved = 0;
  stats.seq = resp->seq;
  stats.offset_ns = g_sched_servo.last_offset_ns;
  stats.delay_ns = g_sched_servo.last_delay_ns;
  stats.freq_corr_ppm = sched_servo_fixed_freq_ppm(&g_sched_servo);

  tud_vendor_write(&stats, sizeof(stats));
  tud_vendor_write_flush();
}

// TinyUSB vendor RX callback
void tud_vendor_rx_cb(uint8_t idx, const uint8_t *buffer, uint32_t bufsize) {
  // printf("Got vendor usb msg, buffer: %p, size: %ld\n", buffer, bufsize);

  if (bufsize == 0)
    return;
  uint8_t msg_type = buffer[0];
  printf("msg_type: %" PRIu8 ", bufsize: %u\n", buffer[0], bufsize);
  if (msg_type == SYNC_MSG_TYPE_RESP && bufsize == sizeof(sync_resp_t)) {
    printf("Sync resp\n");
    sync_resp_t resp;
    memcpy(&resp, buffer, sizeof(resp));
    handle_sync_resp(&resp);
  } else if (msg_type == SYNC_MSG_TYPE_HELLO &&
             bufsize == sizeof(sync_hello_t)) {
    printf("Host says Hello\n");
    zero_clock();
    scheduler_time_ns = 0;
    sync_init();
    // can check stuff here if we want
    // sync_hello_t hello;
    // memcpy(&hello, buf, sizeof(resp));
    g_host_ready = 1;
  }
  printf("Done with rx cb\n");
}
