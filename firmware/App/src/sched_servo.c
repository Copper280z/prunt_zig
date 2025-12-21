
#include "sched_servo.h"
#include "stm32h7xx.h"
#include <limits.h>
#include <stdint.h>
#include <stdio.h>

#define LOWPASS(output, input, c_lowpass)                                      \
  (output += (c_lowpass) * ((input) - (output)))

static int32_t clamp_int32(int32_t v, int32_t lo, int32_t hi) {
  if (v < lo)
    return lo;
  if (v > hi)
    return hi;
  return v;
}

void sched_servo_fixed_init(sched_servo_fixed_t *s, uint32_t base_counts,
                            uint32_t min_counts, uint32_t max_counts,
                            int32_t Kp_fp, int32_t Ki_fp) {
  s->base_counts = base_counts;
  s->min_counts = min_counts;
  s->max_counts = max_counts;
  s->Kp_fp = Kp_fp;
  s->Ki_fp = Ki_fp;
  s->freq_corr_fp = 0;
  s->integrator = 0;
  s->last_offset_ns = 0;
  s->last_delay_ns = 0;
}

// 4-timestamp PI servo
void sched_servo_fixed_on_sync(sched_servo_fixed_t *s, uint64_t t0_node_ns,
                               uint64_t t1_host_ns, uint64_t t2_host_ns,
                               uint64_t t3_node_ns) {
  // t0 and t3 are on device
  int64_t t3_minus_t0 = (int64_t)(t3_node_ns - t0_node_ns);
  int64_t t2_minus_t1 = (int64_t)(t2_host_ns - t1_host_ns);
  int64_t t1_minus_t0 = (int64_t)(t1_host_ns - t0_node_ns);
  int64_t t2_minus_t3 = (int64_t)(t2_host_ns - t3_node_ns);

  int64_t delay_ns =
      (t3_minus_t0 - t2_minus_t1) / 2; // average one way trip time
  int64_t offset_ns = (t1_minus_t0 + t2_minus_t3) /
                      2; // absolute differencce between node and host clock

  printf("delay: %lld\n", delay_ns);
  printf("offset: %lld\n", offset_ns);
  printf("apparent offset drift: %lld\n", offset_ns - s->last_offset_ns);
  printf("freq_corr_fp: %d\n", s->freq_corr_fp);
  printf("scheduler arr: %d\n", TIM24->ARR);
  s->last_delay_ns = delay_ns;
  s->last_offset_ns = offset_ns;
  int64_t abs_delay = (delay_ns >= 0) ? delay_ns : -delay_ns;
  const int64_t MAX_DELAY_NS = 500000; // 500 us
  if (abs_delay > MAX_DELAY_NS) {
    printf("warning: big delay!\n");
    return; // ignore outlier
  }

  // Error in timer ticks
  int32_t err_ticks =
      (int32_t)(offset_ns - (2 * delay_ns) / SERVO_TIMER_TICK_NS);

  printf("err_ticks: %d\n", err_ticks);
  // Integrate (with clamp)
  const int32_t MAX_FREQ_FP = (int32_t)((200 * SERVO_FP_ONE) / 1000); // ~0.002
  int32_t integ = s->integrator + err_ticks;
  // s->integrator = clamp_int32(integ, -INT32_MAX / ((2 * s->Ki_fp) / 3),
  //                             INT32_MAX / ((2 * s->Ki_fp) / 3));
  s->integrator = clamp_int32(integ, -INT32_MAX, INT32_MAX);
  printf("integrator: %d\n", s->integrator);
  // P term: Q16.16 * int32 -> Q16.16
  int64_t p_tmp = (int64_t)s->Kp_fp * (int64_t)err_ticks;
  int32_t p_term_fp = (int32_t)(p_tmp >> SERVO_FP_SHIFT);

  // I term: Q16.16 * int32 -> Q16.16
  int64_t i_tmp = (int64_t)s->Ki_fp * (int64_t)s->integrator;
  int32_t i_term_fp = (int32_t)(i_tmp >> SERVO_FP_SHIFT);

  int32_t delta_fp = p_term_fp + i_term_fp;
  // int32_t new_freq = s->freq_corr_fp - delta_fp;
  int32_t new_freq = -delta_fp;

  // Clamp freq correction to ~±2000 ppm (0.002)
  static float freq_corr = 1200;
  LOWPASS(freq_corr, (float)clamp_int32(new_freq, -MAX_FREQ_FP, MAX_FREQ_FP),
          0.05f);
  s->freq_corr_fp = freq_corr;
}

uint32_t sched_servo_fixed_next_arr(const sched_servo_fixed_t *s) {
  int64_t mul = (int64_t)s->base_counts * (int64_t)s->freq_corr_fp;
  int32_t delta_counts = (int32_t)(mul >> SERVO_FP_SHIFT);
  int32_t counts = (int32_t)s->base_counts + delta_counts;

  if (counts < (int32_t)s->min_counts)
    counts = (int32_t)s->min_counts;
  if (counts > (int32_t)s->max_counts)
    counts = (int32_t)s->max_counts;

  return (uint32_t)(counts - 1);
}

// For logging: convert freq_corr_fp (Q16.16) to ppm
int32_t sched_servo_fixed_freq_ppm(const sched_servo_fixed_t *s) {
  // freq_corr_real = freq_corr_fp / 2^16
  // ppm = freq_corr_real * 1e6
  int64_t tmp = (int64_t)s->freq_corr_fp * 1000000LL;
  return (int32_t)(tmp >> SERVO_FP_SHIFT);
}
