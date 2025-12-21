#pragma once
#include <stdint.h>

void tim5_init(void);
uint64_t node_time_now_ns(void);
void zero_clock();
