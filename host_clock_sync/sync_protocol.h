#pragma once
#include <stdint.h>

#define SYNC_MSG_TYPE_REQ 1   // device -> host
#define SYNC_MSG_TYPE_RESP 2  // host   -> device
#define SYNC_MSG_TYPE_STATS 3 // device -> host
#define SYNC_MSG_TYPE_HELLO 4 // host -> device
#pragma pack(push, 1)

// Device -> Host: sync request
typedef struct {
  uint8_t msg_type; // SYNC_MSG_TYPE_REQ
  uint8_t reserved;
  uint16_t seq;   // sequence number
  uint64_t t0_ns; // node send timestamp (ns, node clock)
} sync_req_t;

// Host -> Device: sync response
typedef struct {
  uint8_t msg_type; // SYNC_MSG_TYPE_RESP
  uint8_t reserved;
  uint16_t seq;   // echo of request seq
  uint64_t t1_ns; // host RX timestamp (ns, host clock)
  uint64_t t2_ns; // host TX timestamp (ns, host clock)
} sync_resp_t;

typedef struct {
  uint8_t msg_type; // SYNC_MSG_TYPE_HELLO
  uint8_t reserved;
  uint16_t reserved2;
  uint32_t protocol_version; // e.g. 1
} sync_hello_t;

// Device -> Host: status / stats after each sync
typedef struct {
  uint8_t msg_type; // SYNC_MSG_TYPE_STATS
  uint8_t reserved;
  uint16_t seq;          // seq of the sync this refers to
  int64_t offset_ns;     // node - host offset estimate
  int64_t delay_ns;      // path delay estimate
  int32_t freq_corr_ppm; // current frequency correction in ppm
} sync_stats_t;

#pragma pack(pop)
