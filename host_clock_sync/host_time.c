#include "host_time.h"
#include <time.h>

static uint64_t clock_offset = 0;

uint64_t host_time_now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC_RAW, &ts);
  return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec -
         clock_offset;
}

void zero_clock() {
  clock_offset = 0;
  clock_offset = host_time_now_ns();
}
