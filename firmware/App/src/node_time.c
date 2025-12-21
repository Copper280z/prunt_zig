#include "node_time.h"
#include "stm32h7xx.h"

#define TIM5_CLK_HZ 10000000UL // 10 MHz
#define TICK_NS 100LL          // 1 / 10MHz = 100 ns

static volatile uint32_t tim5_overflows = 0;

static uint64_t clock_offset = 0;

void tim5_init(void) {

  __HAL_RCC_TIM5_CLK_ENABLE();
  // Prescale core clock to 10 MHz
  TIM5->PSC = (137500000UL / TIM5_CLK_HZ) - 1;
  TIM5->ARR = 0xFFFFFFFF;
  TIM5->CR1 = TIM_CR1_CEN;

  // Enable update interrupt to extend to 64 bits
  TIM5->DIER |= TIM_DIER_UIE;
  NVIC_EnableIRQ(TIM5_IRQn);
}

void TIM5_IRQHandler(void) {
  if (TIM5->SR & TIM_SR_UIF) {
    TIM5->SR &= ~TIM_SR_UIF;
    tim5_overflows++;
  }
}

uint64_t node_time_now_ns(void) {
  uint32_t hi1 = tim5_overflows;
  uint32_t lo = TIM5->CNT;
  uint32_t hi2 = tim5_overflows;

  if (hi2 != hi1 && (TIM5->SR & TIM_SR_UIF)) {
    hi1 = hi2;
    lo = TIM5->CNT;
  }

  uint64_t ticks = ((uint64_t)hi1 << 32) | lo;
  return ticks * TICK_NS - clock_offset;
}

void zero_clock() {
  // __disable_irq();
  clock_offset = 0;
  clock_offset = node_time_now_ns();
  // __enable_irq();
}
