/* USER CODE BEGIN Header */
/**
 ******************************************************************************
 * @file           : main.c
 * @brief          : Main program body
 ******************************************************************************
 * @attention
 *
 * Copyright (c) 2024 STMicroelectronics.
 * All rights reserved.
 *
 * This software is licensed under terms that can be found in the LICENSE file
 * in the root directory of this software component.
 * If no LICENSE file comes with this software, it is provided AS-IS.
 *
 ******************************************************************************
 */
/* USER CODE END Header */
/* Includes ------------------------------------------------------------------*/
#include "main.h"
#include "adc.h"
#include "gpio.h"
#include "lptim.h"
#include "spi.h"
#include "stm32h7xx_hal.h"
#include "stm32h7xx_hal_gpio.h"
#include "tim.h"
#include "usart.h"
#include "usb_otg.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */
#include "../../App/src/scheduler_timer.c"
#include "../../App/src/usb_descriptors.c"
#include "usbd.h"
#define VENDOR_REQUEST_CUSTOM_COMMAND 42
#define min(a, b) (((a) < (b)) ? (a) : (b))
#include "SEGGER_RTT.h"
#include "node_time.h"
#include "sched_servo.h"
#include "tusb.h"
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

int __io_putchar(int ch) {
  SEGGER_RTT_PutChar(0, ch);
  // tud_cdc_n_write_char(1, ch);
  // tud_cdc_n_write_str(0, "putchar!\n");
  // tud_cdc_n_write_flush(0);
  // if (ch == '\n') {
  //   tud_cdc_n_write_flush(0);
  // }
  return ch;
}
/* USER CODE END Includes */

/* Private typedef -----------------------------------------------------------*/
/* USER CODE BEGIN PTD */
// void OTG_FS_IRQHandler(void) { tusb_int_handler(0, true); }
void OTG_HS_IRQHandler(void) {
  tud_int_handler(1);
  // tusb_int_handler(0, true);
  // printf("USB IRQ\n");
}
void OTG_HS_EP1_IN_IRQHandler(void) {
  printf("USB EP1 IN IRQ\n");
  tusb_int_handler(1, true);
};
void OTG_HS_EP1_OUT_IRQHandler(void) {
  printf("USB EP1 OUT IRQ\n");
  tusb_int_handler(1, true);
};

// uint8_t to_send[6] = {0, 1, 2, 3, 4, 5};
// uint8_t rxbuf[64] = {0};
// bool custom_command_cb(uint8_t rhport, uint8_t stage,
//                        tusb_control_request_t const *request) {
//   bool result = false;
//   int len = 0;
//
//   if (rhport != BOARD_TUD_RHPORT)
//     return result;
//
//   if (request->bmRequestType_bit.direction == TUSB_DIR_IN) {
//     // TUSB_DIR_IN
//     switch (stage) {
//     case CONTROL_STAGE_SETUP:
//       printf("SETUP stage of control transfer IN\n");
//       result = tud_control_xfer(rhport, request, &to_send, sizeof(to_send));
//       break;
//     case CONTROL_STAGE_DATA:
//       printf("DATA stage of control transfer IN\n");
//       result = true;
//       break;
//     case CONTROL_STAGE_ACK:
//       result = true;
//       break;
//     default:
//       break;
//     }
//   } else {
//     // TUSB_DIR_OUT
//     switch (stage) {
//     case CONTROL_STAGE_SETUP: {
//       if (request->wValue == 0xbeef) {
//         // HAL_GPIO_WritePin(LED_RED_GPIO_Port, LED_RED_Pin,
//         (GPIO_PinState)0);
//       } else {
//         // HAL_GPIO_WritePin(LED_RED_GPIO_Port, LED_RED_Pin,
//         (GPIO_PinState)1);
//       }
//     }
//       // result = tud_control_status(rhport, request);
//       len = min(request->wLength, 64);
//       result = tud_control_xfer(rhport, request, rxbuf, len);
//       printf("recieved: ");
//       for (int i = 0; i < len; i++) {
//         printf("%d, ", rxbuf[i]);
//       }
//       printf("\n");
//       break;
//     case CONTROL_STAGE_DATA:
//       printf("DATA stage of control transfer OUT\n");
//       len = min(request->wLength, 64);
//       // result = tud_control_xfer(rhport, request, rxbuf, 0);
//       printf("recieved: ");
//       for (int i = 0; i < len; i++) {
//         printf("%d, ", rxbuf[i]);
//         rxbuf[i] = 0;
//       }
//       printf("\n");
//       result = true;
//       break;
//     case CONTROL_STAGE_ACK:
//       printf("ACK control OUT transfer\n");
//       // len = min(request->wLength, 64);
//       result = true; // tud_control_status(rhport, request);
//       break;
//     default:
//       printf("custom command default branch\n");
//       break;
//     }
//   }
//   return result;
// }
//
// bool tud_vendor_control_xfer_cb(uint8_t rhport, uint8_t stage,
//                                 tusb_control_request_t const *request) {
//   uint8_t recipient = request->bmRequestType_bit.recipient;
//   uint8_t type = request->bmRequestType_bit.type;
//   uint8_t direction = request->bmRequestType_bit.direction;
//
//   printf("Control xfer:\n stage: %d\nrecipient: %d\ntype: %d\ndirection: "
//          "%d\nbRequest: %d\nwValue: 0x%x\nwIndex: %d\nwLength: %d\n\n",
//          stage, recipient, type, direction, request->bRequest,
//          request->wValue, request->wIndex, request->wLength);
//
//   bool result = false;
//   switch (request->bmRequestType_bit.type) {
//   case TUSB_REQ_TYPE_VENDOR:
//     switch (request->bRequest) {
//     case VENDOR_REQUEST_CUSTOM_COMMAND:
//       result = custom_command_cb(rhport, stage, request);
//       break;
//     }
//     break;
//   case TUSB_REQ_TYPE_STANDARD:
//     break;
//   case TUSB_REQ_TYPE_CLASS:
//     break;
//   default:
//     break;
//   }
//   printf("result: %d\n", result);
//   printf("********\n\n");
//   return result;
// }
void Enable_USB_IRQs() {
  // HAL_NVIC_SetPriority(OTG_HS_EP1_OUT_IRQn, 0, 0);
  // HAL_NVIC_EnableIRQ(OTG_HS_EP1_OUT_IRQn);
  // HAL_NVIC_SetPriority(OTG_HS_EP1_IN_IRQn, 0, 0);
  // HAL_NVIC_EnableIRQ(OTG_HS_EP1_IN_IRQn);
  HAL_NVIC_SetPriority(OTG_HS_IRQn, 1, 0);
  HAL_NVIC_EnableIRQ(OTG_HS_IRQn);
}

/* USER CODE END PTD */

/* Private define ------------------------------------------------------------*/
/* USER CODE BEGIN PD */

/* USER CODE END PD */

/* Private macro -------------------------------------------------------------*/
/* USER CODE BEGIN PM */

/* USER CODE END PM */

/* Private variables ---------------------------------------------------------*/

/* USER CODE BEGIN PV */
#define USBULPI_PHYCR ((uint32_t)(0x40040000 + 0x034))
#define USBULPI_D07 ((uint32_t)0x000000FF)
#define USBULPI_New ((uint32_t)0x02000000)
#define USBULPI_RW ((uint32_t)0x00400000)
#define USBULPI_S_BUSY ((uint32_t)0x04000000)
#define USBULPI_S_DONE ((uint32_t)0x08000000)

#define Pattern_55 ((uint32_t)0x00000055)
#define Pattern_AA ((uint32_t)0x000000AA)

#define PHY_PWR_DOWN (1 << 11)
#define PHY_ADDRESS 0x00 /* default ADDR for PHY: LAN8742 */
#define USBULPI_TIMEOUT_COUNT (100)

#define USB_OTG_READ_REG32(reg) (*(__IO uint32_t *)(reg))
#define USB_OTG_WRITE_REG32(reg, value) (*(__IO uint32_t *)(reg) = (value))

/**
 * @brief  Read CR value
 * @param  Addr the Address of the ULPI Register
 * @retval Returns value of PHY CR register
 */
static uint32_t USB_ULPI_Read(uint32_t Addr) {
  uint32_t val = 0;
  uint32_t timeout = USBULPI_TIMEOUT_COUNT;

  USB_OTG_WRITE_REG32(USBULPI_PHYCR, USBULPI_New | (Addr << 16));
  val = USB_OTG_READ_REG32(USBULPI_PHYCR);
  while (((val & USBULPI_S_DONE) == 0) && (timeout--)) {
    val = USB_OTG_READ_REG32(USBULPI_PHYCR);
  }
  val = USB_OTG_READ_REG32(USBULPI_PHYCR);
  return val & 0x000000ff;
}

/**
 * @brief  Write CR value
 * @param  Addr the Address of the ULPI Register
 * @param  Data Data to write
 * @retval Returns value of PHY CR register
 */
static uint32_t USB_ULPI_Write(uint32_t Addr, uint32_t Data) {
  uint32_t val;
  uint32_t timeout = USBULPI_TIMEOUT_COUNT;

  USB_OTG_WRITE_REG32(USBULPI_PHYCR, USBULPI_New | USBULPI_RW | (Addr << 16) |
                                         (Data & 0x000000ff));
  val = USB_OTG_READ_REG32(USBULPI_PHYCR);
  while (((val & USBULPI_S_DONE) == 0) && (timeout--)) {
    val = USB_OTG_READ_REG32(USBULPI_PHYCR);
  }

  val = USB_OTG_READ_REG32(USBULPI_PHYCR);
  return 0;
}

// sched_servo_fixed_t g_sched_servo;

/* USER CODE END PV */

/* Private function prototypes -----------------------------------------------*/
void SystemClock_Config(void);
void PeriphCommonClock_Config(void);
static void MPU_Config(void);
/* USER CODE BEGIN PFP */

/* USER CODE END PFP */

/* Private user code ---------------------------------------------------------*/
/* USER CODE BEGIN 0 */

/* USER CODE END 0 */

/**
 * @brief  The application entry point.
 * @retval int
 */
int main(void) {

  /* USER CODE BEGIN 1 */

  /* USER CODE END 1 */

  /* MPU Configuration--------------------------------------------------------*/
  MPU_Config();

  /* Enable the CPU Cache */

  /* Enable I-Cache---------------------------------------------------------*/
  SCB_EnableICache();

  /* Enable D-Cache---------------------------------------------------------*/
  SCB_EnableDCache();

  /* MCU Configuration--------------------------------------------------------*/

  /* Reset of all peripherals, Initializes the Flash interface and the Systick.
   */
  HAL_Init();

  /* USER CODE BEGIN Init */
  SEGGER_RTT_Init();
  SEGGER_RTT_ConfigUpBuffer(0, NULL, NULL, 0, SEGGER_RTT_MODE_NO_BLOCK_SKIP);
  /* USER CODE END Init */

  /* Configure the system clock */
  SystemClock_Config();

  /* Configure the peripherals common clocks */
  PeriphCommonClock_Config();

  /* USER CODE BEGIN SysInit */

  /* USER CODE END SysInit */

  /* Initialize all configured peripherals */
  MX_GPIO_Init();
  MX_ADC1_Init();
  MX_ADC2_Init();
  MX_TIM1_Init();
  MX_TIM8_Init();
  MX_SPI3_Init();
  MX_TIM3_Init();
  MX_TIM4_Init();
  MX_ADC3_Init();
  MX_LPTIM2_Init();
  MX_SPI1_Init();
  MX_SPI2_Init();
  MX_TIM2_Init();
  MX_TIM23_Init();
  MX_UART5_Init();
  MX_USART2_UART_Init();
  MX_USART3_UART_Init();
  MX_USB_OTG_HS_PCD_Init();
  MX_TIM5_Init();
  MX_TIM6_Init();
  MX_TIM24_Init();
  /* USER CODE BEGIN 2 */

  Enable_USB_IRQs();

  HAL_GPIO_WritePin(GPIOB, GPIO_PIN_8, GPIO_PIN_SET);
  HAL_Delay(100);
  HAL_GPIO_WritePin(GPIOB, GPIO_PIN_8, GPIO_PIN_RESET);
  // do a software reset of the ULPI Phy before we init the usb periph
  // following the tinyusb example lead on this one
  // HAL_Delay(20);
  // uint32_t ulpi_reg = USB_ULPI_Read(0x04);
  // USB_ULPI_Write(0x04, ulpi_reg | 1 << 5);
  // HAL_Delay(20);

  // printf("Starting tinyusb\n");
  tusb_rhport_init_t dev_init = {.role = TUSB_ROLE_DEVICE,
                                 .speed = TUSB_SPEED_HIGH};
  bool initial_init = tusb_rhport_init(1, &dev_init);
  if (!initial_init) {
    printf("USB Init failed :(, %d\n", initial_init);
    while (1) {
      HAL_Delay(100);
    }
  }
  USB_OTG_HS->GOTGCTL &= ~USB_OTG_GOTGCTL_BVALOEN;
  printf("tinyusb started!\n");
  sync_init();
  tim5_init();
  tim_init_for_scheduler();
  /* USER CODE END 2 */

  /* Infinite loop */
  /* USER CODE BEGIN WHILE */
  uint32_t blink_last = board_millis();
  while (1) {
    // uint64_t t_now = node_time_now_ns();
    // printf("time ns: %llu\n", t_now);
    if (board_millis() - blink_last > 500) {
      HAL_GPIO_TogglePin(GPIOE, GPIO_PIN_1);
      blink_last = board_millis();
      // tud_cdc_n_write_str(0, "blink\n");
      // tud_cdc_n_write_flush(0);
    }

    // printf("GINTSTS: %d\n", USB_OTG_HS->GINTSTS);
    int sess_valid = 1 & (USB_OTG_HS->GOTGCTL >> 18);
    // uint32_t sess_valid = USB_OTG_HS->GOTGCTL;
    bool usb_inited = tud_inited();
    int connected = tud_connected();
    int mounted = tud_mounted();
    printf("GOTGCTL: %d, inited: %d, connected: %d, mounted %d\n", sess_valid,
           usb_inited, connected, mounted);
    // if (sess_valid && !connected) {
    //   tud_connect();
    // }
    // if (sess_valid && usb_inited && ~mounted) {
    //   tud_disconnect();
    //   // int deinit = tusb_deinit(1);
    //   // printf("usb deinit: %d\n", deinit);
    // } else if (sess_valid && ~usb_inited) {
    //   // tud_init(1);
    //   tud_connect();
    //   printf("usb init\n");
    // } else if (usb_inited) {
    //   tud_task();
    // }
    board_delay(1000);

    /* USER CODE END WHILE */

    /* USER CODE BEGIN 3 */
  }
  /* USER CODE END 3 */
}

/**
 * @brief System Clock Configuration
 * @retval None
 */
void SystemClock_Config(void) {
  RCC_OscInitTypeDef RCC_OscInitStruct = {0};
  RCC_ClkInitTypeDef RCC_ClkInitStruct = {0};

  /** Supply configuration update enable
   */
  HAL_PWREx_ConfigSupply(PWR_LDO_SUPPLY);

  /** Configure the main internal regulator output voltage
   */
  __HAL_PWR_VOLTAGESCALING_CONFIG(PWR_REGULATOR_VOLTAGE_SCALE0);

  while (!__HAL_PWR_GET_FLAG(PWR_FLAG_VOSRDY)) {
  }

  /** Initializes the RCC Oscillators according to the specified parameters
   * in the RCC_OscInitTypeDef structure.
   */
  RCC_OscInitStruct.OscillatorType = RCC_OSCILLATORTYPE_HSE;
  RCC_OscInitStruct.HSEState = RCC_HSE_BYPASS;
  RCC_OscInitStruct.PLL.PLLState = RCC_PLL_ON;
  RCC_OscInitStruct.PLL.PLLSource = RCC_PLLSOURCE_HSE;
  RCC_OscInitStruct.PLL.PLLM = 1;
  RCC_OscInitStruct.PLL.PLLN = 110;
  RCC_OscInitStruct.PLL.PLLP = 1;
  RCC_OscInitStruct.PLL.PLLQ = 5;
  RCC_OscInitStruct.PLL.PLLR = 2;
  RCC_OscInitStruct.PLL.PLLRGE = RCC_PLL1VCIRANGE_2;
  RCC_OscInitStruct.PLL.PLLVCOSEL = RCC_PLL1VCOWIDE;
  RCC_OscInitStruct.PLL.PLLFRACN = 0;
  if (HAL_RCC_OscConfig(&RCC_OscInitStruct) != HAL_OK) {
    Error_Handler();
  }

  /** Initializes the CPU, AHB and APB buses clocks
   */
  RCC_ClkInitStruct.ClockType = RCC_CLOCKTYPE_HCLK | RCC_CLOCKTYPE_SYSCLK |
                                RCC_CLOCKTYPE_PCLK1 | RCC_CLOCKTYPE_PCLK2 |
                                RCC_CLOCKTYPE_D3PCLK1 | RCC_CLOCKTYPE_D1PCLK1;
  RCC_ClkInitStruct.SYSCLKSource = RCC_SYSCLKSOURCE_PLLCLK;
  RCC_ClkInitStruct.SYSCLKDivider = RCC_SYSCLK_DIV1;
  RCC_ClkInitStruct.AHBCLKDivider = RCC_HCLK_DIV2;
  RCC_ClkInitStruct.APB3CLKDivider = RCC_APB3_DIV2;
  RCC_ClkInitStruct.APB1CLKDivider = RCC_APB1_DIV2;
  RCC_ClkInitStruct.APB2CLKDivider = RCC_APB2_DIV2;
  RCC_ClkInitStruct.APB4CLKDivider = RCC_APB4_DIV2;

  if (HAL_RCC_ClockConfig(&RCC_ClkInitStruct, FLASH_LATENCY_3) != HAL_OK) {
    Error_Handler();
  }
}

/**
 * @brief Peripherals Common Clock Configuration
 * @retval None
 */
void PeriphCommonClock_Config(void) {
  RCC_PeriphCLKInitTypeDef PeriphClkInitStruct = {0};

  /** Initializes the peripherals clock
   */
  PeriphClkInitStruct.PeriphClockSelection =
      RCC_PERIPHCLK_ADC | RCC_PERIPHCLK_LPTIM2 | RCC_PERIPHCLK_SPI3 |
      RCC_PERIPHCLK_SPI2 | RCC_PERIPHCLK_SPI1;
  PeriphClkInitStruct.PLL2.PLL2M = 1;
  PeriphClkInitStruct.PLL2.PLL2N = 100;
  PeriphClkInitStruct.PLL2.PLL2P = 8;
  PeriphClkInitStruct.PLL2.PLL2Q = 2;
  PeriphClkInitStruct.PLL2.PLL2R = 2;
  PeriphClkInitStruct.PLL2.PLL2RGE = RCC_PLL2VCIRANGE_2;
  PeriphClkInitStruct.PLL2.PLL2VCOSEL = RCC_PLL2VCOWIDE;
  PeriphClkInitStruct.PLL2.PLL2FRACN = 0;
  PeriphClkInitStruct.Spi123ClockSelection = RCC_SPI123CLKSOURCE_PLL2;
  PeriphClkInitStruct.Lptim2ClockSelection = RCC_LPTIM2CLKSOURCE_PLL2;
  PeriphClkInitStruct.AdcClockSelection = RCC_ADCCLKSOURCE_PLL2;
  if (HAL_RCCEx_PeriphCLKConfig(&PeriphClkInitStruct) != HAL_OK) {
    Error_Handler();
  }
}

/* USER CODE BEGIN 4 */

/* USER CODE END 4 */

/* MPU Configuration */

void MPU_Config(void) {
  MPU_Region_InitTypeDef MPU_InitStruct = {0};

  /* Disables the MPU */
  HAL_MPU_Disable();

  /** Initializes and configures the Region and the memory to be protected
   */
  MPU_InitStruct.Enable = MPU_REGION_ENABLE;
  MPU_InitStruct.Number = MPU_REGION_NUMBER0;
  MPU_InitStruct.BaseAddress = 0x0;
  MPU_InitStruct.Size = MPU_REGION_SIZE_4GB;
  MPU_InitStruct.SubRegionDisable = 0x87;
  MPU_InitStruct.TypeExtField = MPU_TEX_LEVEL0;
  MPU_InitStruct.AccessPermission = MPU_REGION_NO_ACCESS;
  MPU_InitStruct.DisableExec = MPU_INSTRUCTION_ACCESS_DISABLE;
  MPU_InitStruct.IsShareable = MPU_ACCESS_SHAREABLE;
  MPU_InitStruct.IsCacheable = MPU_ACCESS_NOT_CACHEABLE;
  MPU_InitStruct.IsBufferable = MPU_ACCESS_NOT_BUFFERABLE;

  HAL_MPU_ConfigRegion(&MPU_InitStruct);
  /* Enables the MPU */
  HAL_MPU_Enable(MPU_PRIVILEGED_DEFAULT);
}

/**
 * @brief  This function is executed in case of error occurrence.
 * @retval None
 */
void Error_Handler(void) {
  /* USER CODE BEGIN Error_Handler_Debug */
  /* User can add his own implementation to report the HAL error return state */
  __disable_irq();
  while (1) {
  }
  /* USER CODE END Error_Handler_Debug */
}
#ifdef USE_FULL_ASSERT
/**
 * @brief  Reports the name of the source file and the source line number
 *         where the assert_param error has occurred.
 * @param  file: pointer to the source file name
 * @param  line: assert_param error line source number
 * @retval None
 */
void assert_failed(uint8_t *file, uint32_t line) {
  /* USER CODE BEGIN 6 */
  /* User can add his own implementation to report the file name and line
     number, ex: printf("Wrong parameters value: file %s on line %d\r\n", file,
     line) */
  /* USER CODE END 6 */
}
#endif /* USE_FULL_ASSERT */
