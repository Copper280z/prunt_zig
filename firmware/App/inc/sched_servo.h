#pragma once
#include <stdint.h>

#define SERVO_FP_SHIFT 16
#define SERVO_FP_ONE (1L << SERVO_FP_SHIFT)
#define SERVO_TIMER_TICK_NS 100LL // 10 MHz timer => 100 ns

typedef struct {
  uint32_t base_counts; // nominal counts per scheduler tick (e.g. 10000)
  uint32_t min_counts;  // safety lower bound (e.g. 9500)
  uint32_t max_counts;  // safety upper bound (e.g. 10500)

  int32_t Kp_fp; // Q16.16 proportional gain
  int32_t Ki_fp; // Q16.16 integral gain

  int32_t freq_corr_fp; // Q16.16 fractional frequency correction
  int32_t integrator;   // integrated error in timer ticks

  int64_t last_offset_ns;
  int64_t last_delay_ns;
} sched_servo_fixed_t;

void sched_servo_fixed_init(sched_servo_fixed_t *s, uint32_t base_counts,
                            uint32_t min_counts, uint32_t max_counts,
                            int32_t Kp_fp, int32_t Ki_fp);

void sched_servo_fixed_on_sync(sched_servo_fixed_t *s, uint64_t t0_node_ns,
                               uint64_t t1_host_ns, uint64_t t2_host_ns,
                               uint64_t t3_node_ns);

uint32_t sched_servo_fixed_next_arr(const sched_servo_fixed_t *s);

int32_t sched_servo_fixed_freq_ppm(const sched_servo_fixed_t *s);
