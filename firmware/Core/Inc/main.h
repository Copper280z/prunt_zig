/* USER CODE BEGIN Header */
/**
  ******************************************************************************
  * @file           : main.h
  * @brief          : Header for main.c file.
  *                   This file contains the common defines of the application.
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

/* Define to prevent recursive inclusion -------------------------------------*/
#ifndef __MAIN_H
#define __MAIN_H

#ifdef __cplusplus
extern "C" {
#endif

/* Includes ------------------------------------------------------------------*/
#include "stm32h7xx_hal.h"

/* Private includes ----------------------------------------------------------*/
/* USER CODE BEGIN Includes */

/* USER CODE END Includes */

/* Exported types ------------------------------------------------------------*/
/* USER CODE BEGIN ET */

/* USER CODE END ET */

/* Exported constants --------------------------------------------------------*/
/* USER CODE BEGIN EC */

/* USER CODE END EC */

/* Exported macro ------------------------------------------------------------*/
/* USER CODE BEGIN EM */

/* USER CODE END EM */

/* Exported functions prototypes ---------------------------------------------*/
void Error_Handler(void);

/* USER CODE BEGIN EFP */

/* USER CODE END EFP */

/* Private defines -----------------------------------------------------------*/
#define EN_GATE_Pin GPIO_PIN_2
#define EN_GATE_GPIO_Port GPIOE
#define nFAULT_2_Pin GPIO_PIN_3
#define nFAULT_2_GPIO_Port GPIOE
#define nFAULT_3_Pin GPIO_PIN_4
#define nFAULT_3_GPIO_Port GPIOE
#define nFAULT_4_Pin GPIO_PIN_5
#define nFAULT_4_GPIO_Port GPIOE
#define DC_CAL_Pin GPIO_PIN_6
#define DC_CAL_GPIO_Port GPIOE
#define USR_BTN_Pin GPIO_PIN_13
#define USR_BTN_GPIO_Port GPIOC
#define M4_PHA_TIM23_CH1_Pin GPIO_PIN_0
#define M4_PHA_TIM23_CH1_GPIO_Port GPIOF
#define M4_PHA_TIM23_CH2_Pin GPIO_PIN_1
#define M4_PHA_TIM23_CH2_GPIO_Port GPIOF
#define nFAULT_Pin GPIO_PIN_2
#define nFAULT_GPIO_Port GPIOF
#define VPDD_4_ADC3_IN5_Pin GPIO_PIN_3
#define VPDD_4_ADC3_IN5_GPIO_Port GPIOF
#define VPDD_3_ADC3_IN4_Pin GPIO_PIN_5
#define VPDD_3_ADC3_IN4_GPIO_Port GPIOF
#define VPDD_2_ADC3_IN3_Pin GPIO_PIN_7
#define VPDD_2_ADC3_IN3_GPIO_Port GPIOF
#define VPDD_1_ADC3_IN2_Pin GPIO_PIN_9
#define VPDD_1_ADC3_IN2_GPIO_Port GPIOF
#define M4_CS_B_ADC2_IN11_Pin GPIO_PIN_1
#define M4_CS_B_ADC2_IN11_GPIO_Port GPIOC
#define M3_PHA_TIM2_CH1_Pin GPIO_PIN_0
#define M3_PHA_TIM2_CH1_GPIO_Port GPIOA
#define M3_PHB_TIM2_CH2_Pin GPIO_PIN_1
#define M3_PHB_TIM2_CH2_GPIO_Port GPIOA
#define M3_PHC_TIM2_CH3_Pin GPIO_PIN_2
#define M3_PHC_TIM2_CH3_GPIO_Port GPIOA
#define M2_CS_A_ADC1_IN3_Pin GPIO_PIN_6
#define M2_CS_A_ADC1_IN3_GPIO_Port GPIOA
#define ENC1_B_TIM3_CH2_Pin GPIO_PIN_7
#define ENC1_B_TIM3_CH2_GPIO_Port GPIOA
#define M2_CS_B_ADC2_IN4_Pin GPIO_PIN_4
#define M2_CS_B_ADC2_IN4_GPIO_Port GPIOC
#define M4_CS_A_ADC1_IN8_Pin GPIO_PIN_5
#define M4_CS_A_ADC1_IN8_GPIO_Port GPIOC
#define MDRV_SDI_SPI3_MOSI_Pin GPIO_PIN_2
#define MDRV_SDI_SPI3_MOSI_GPIO_Port GPIOB
#define M1_CS_A_ADC1_IN2_Pin GPIO_PIN_11
#define M1_CS_A_ADC1_IN2_GPIO_Port GPIOF
#define M3_CS_A_ADC1_IN6_Pin GPIO_PIN_12
#define M3_CS_A_ADC1_IN6_GPIO_Port GPIOF
#define M1_CS_B_ADC2_IN2_Pin GPIO_PIN_13
#define M1_CS_B_ADC2_IN2_GPIO_Port GPIOF
#define M3_CS_B_ADC2_IN6_Pin GPIO_PIN_14
#define M3_CS_B_ADC2_IN6_GPIO_Port GPIOF
#define nOCTW_3_Pin GPIO_PIN_1
#define nOCTW_3_GPIO_Port GPIOG
#define M1_PHA_TIM1_CH1_Pin GPIO_PIN_9
#define M1_PHA_TIM1_CH1_GPIO_Port GPIOE
#define M1_PHB_TIM1_CH2_Pin GPIO_PIN_11
#define M1_PHB_TIM1_CH2_GPIO_Port GPIOE
#define M1_PHC_TIM1_CH3_Pin GPIO_PIN_13
#define M1_PHC_TIM1_CH3_GPIO_Port GPIOE
#define ENC3_B_LPTIM2_IN2_Pin GPIO_PIN_11
#define ENC3_B_LPTIM2_IN2_GPIO_Port GPIOD
#define ENC3_A_LPTIM2_IN1_Pin GPIO_PIN_12
#define ENC3_A_LPTIM2_IN1_GPIO_Port GPIOD
#define ENC2_B_TIM4_CH2_Pin GPIO_PIN_13
#define ENC2_B_TIM4_CH2_GPIO_Port GPIOD
#define nSCS_4_Pin GPIO_PIN_14
#define nSCS_4_GPIO_Port GPIOD
#define nSCS_3_Pin GPIO_PIN_15
#define nSCS_3_GPIO_Port GPIOD
#define nOCTW_2_Pin GPIO_PIN_2
#define nOCTW_2_GPIO_Port GPIOG
#define nOCTW_Pin GPIO_PIN_3
#define nOCTW_GPIO_Port GPIOG
#define nSCS_Pin GPIO_PIN_4
#define nSCS_GPIO_Port GPIOG
#define EN_GATE_4_Pin GPIO_PIN_6
#define EN_GATE_4_GPIO_Port GPIOG
#define EN_GATE_3_Pin GPIO_PIN_7
#define EN_GATE_3_GPIO_Port GPIOG
#define EN_GATE_2_Pin GPIO_PIN_8
#define EN_GATE_2_GPIO_Port GPIOG
#define M2_PHA_TIM8_CH1_Pin GPIO_PIN_6
#define M2_PHA_TIM8_CH1_GPIO_Port GPIOC
#define M2_PHB_TIM8_CH2_Pin GPIO_PIN_7
#define M2_PHB_TIM8_CH2_GPIO_Port GPIOC
#define M2_PHC_TIM8_CH3_Pin GPIO_PIN_8
#define M2_PHC_TIM8_CH3_GPIO_Port GPIOC
#define AUX_SPI_nCS_Pin GPIO_PIN_9
#define AUX_SPI_nCS_GPIO_Port GPIOC
#define MDRV_SCLK_SPI3_SCK_Pin GPIO_PIN_10
#define MDRV_SCLK_SPI3_SCK_GPIO_Port GPIOC
#define MDRV_SDO_SPI3_MISO_Pin GPIO_PIN_11
#define MDRV_SDO_SPI3_MISO_GPIO_Port GPIOC
#define M4_PHC_TIM23_CH3_Pin GPIO_PIN_14
#define M4_PHC_TIM23_CH3_GPIO_Port GPIOG
#define ENC1_A_TIM3_CH1_Pin GPIO_PIN_4
#define ENC1_A_TIM3_CH1_GPIO_Port GPIOB
#define ENC2_A_TIM4_CH1_Pin GPIO_PIN_6
#define ENC2_A_TIM4_CH1_GPIO_Port GPIOB
#define usb_phy_rst_Pin GPIO_PIN_8
#define usb_phy_rst_GPIO_Port GPIOB
#define ENC4_A_LPTIM1_IN1_or_yellow_led_Pin GPIO_PIN_1
#define ENC4_A_LPTIM1_IN1_or_yellow_led_GPIO_Port GPIOE

/* USER CODE BEGIN Private defines */

/* USER CODE END Private defines */

#ifdef __cplusplus
}
#endif

#endif /* __MAIN_H */
