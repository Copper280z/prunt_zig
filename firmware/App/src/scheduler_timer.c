#include "node_sync.c"
#include "sched_servo.h"
#include "stm32h723xx.h"
#include "stm32h7xx.h"

sched_servo_fixed_t g_sched_servo;

void scheduler_tick_handler(void); // your RT “tick” callback

void tim_init_for_scheduler(void) {

  __HAL_RCC_TIM24_CLK_ENABLE();
  // Prescale to 10 MHz
  TIM24->PSC = ((SystemCoreClock / 2) / 10000000UL) - 1;
  //
  uint32_t base_counts = 10000; // 1 ms
  // TIM24->ARR = base_counts - 1;
  //
  TIM24->CR1 = TIM_CR1_ARPE; // enable preload
  //
  TIM24->DIER |= TIM_DIER_UIE;
  HAL_NVIC_SetPriority(TIM24_IRQn, 0, 0);
  NVIC_EnableIRQ(TIM24_IRQn);

  // Need to tune gains better
  int32_t Kp_fp = 50; // ~6.1e-5
  int32_t Ki_fp = 1;  // tiny

  uint32_t min_counts = base_counts - 500; // 0.95 ms
  uint32_t max_counts = base_counts + 500; // 1.05 ms

  sched_servo_fixed_init(&g_sched_servo, base_counts, min_counts, max_counts,
                         Kp_fp, Ki_fp);

  TIM24->CR1 |= TIM_CR1_CEN;
}

void TIM24_IRQHandler(void) {
  if (TIM24->SR & TIM_SR_UIF) {
    TIM24->SR &= ~TIM_SR_UIF;

    scheduler_tick_handler();

    uint32_t next_arr = sched_servo_fixed_next_arr(&g_sched_servo);
    TIM24->ARR = next_arr;
  }
}

uint64_t scheduler_time_ns = 0;
// Stub: you plug in your scheduler or just toggle a pin, etc.
void scheduler_tick_handler(void) {
  // Do whatever periodic work you want here
  scheduler_time_ns += 1e6;
  static uint32_t cnt = 0;
  if (cnt >= 10) {
    cnt = 0;
    // HAL_GPIO_TogglePin(GPIOE, GPIO_PIN_0);
  }
  cnt += 1;
  sync_tick();
}
