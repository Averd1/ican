# DFRobot_matrixLidarDistanceSensor

- [中文版](./README_CN.md)

This is a user library for retrieving TOF sensor raw data and providing obstacle avoidance suggestions.

![](./resources/images/SEN0628.png)

## Product Link (https://www.dfrobot.com)
    SKU:SEN0628

## Table of Contents

* [Summary](#summary)
* [Installation](#installation)
* [Methods](#methods)
* [Compatibility](#compatibility)
* [History](#history)
* [Credits](#credits)

## Summary
This is a user library for retrieving TOF sensor raw data and providing obstacle avoidance suggestions.

## Installation

To use this library, download the library file first, paste it into the \Arduino\libraries directory, then open the examples folder and run the demo in the folder.

## Methods

```C++
    /**
     * @fn begin
     * @brief Initializes the sensor
     * @return NULL
     */
    uint8_t begin(void);

     /**
     * @fn getAllDataConfig
     * @brief Configures the retrieval of all data
     * @param matrix Configuration matrix for sensor sampling
     * @return Returns the configuration status
     * @retval 0 Success
     * @retval 1 Failure
     */
    uint8_t getAllDataConfig(eMatrix_t matrix);

    /**
     * @fn configAvoidance
     * @brief Initializes obstacle avoidance
     * @param wall Configures the obstacle avoidance distance, in centimeters
     */
    uint8_t configAvoidance(uint8_t wall);

    /**
     * @fn getAllData
     * @brief Retrieves all data
     * @param buf Buffer to store the data
     */
    uint8_t getAllData(void *buf);

    /**
     * @fn getFixedPointData
     * @brief Retrieves data for a specific point
     * @param x X coordinate
     * @param y Y coordinate
     * @return Returns the retrieved data
     */
    uint16_t getFixedPointData(uint8_t x, uint8_t y);

    /**
     * @fn requestObstacleSensorData
     * @brief Requests obstacle avoidance data
     * @return Returns the retrieval status
     */
    uint8_t requestObstacleSensorData(void);

    /**
     * @fn getDir
     * @brief Retrieves obstacle avoidance direction suggestions
     * @return Returns the avoidance suggestions
     */
    uint8_t getDir(void);

    /**
     * @fn getEmergencyFlag
     * @brief Retrieves the emergency obstacle avoidance flag
     * @return Returns the obstacle avoidance flag
     */
    uint8_t getEmergencyFlag(void);

    /**
     * @fn getObstacleDistance
     * @brief Requests the distance to obstacles
     * @return Returns the request status
     */
    uint8_t requestObstacleDistance(void);

    /**
     * @fn getDistance
     * @brief Retrieves the distance
     * @return Returns the distance
     */
    uint16_t getDistance(eDir_t dir);


```


## Compatibility

MCU                | Work Well | Work Wrong | Untested  | Remarks
------------------ | :----------: | :----------: | :---------: | -----
Arduino uno |       √      |             |            | 
FireBeetle esp32 |       √      |             |            | 
FireBeetle esp8266 |       √      |             |            | 
FireBeetle m0 |       √      |             |            | 
Leonardo |       √      |             |            | 
Microbit |       √      |             |            | 
Arduino MEGA2560 | √ | | | 


## History

- data 2024-09-09
- version V1.0


## Credits

Written by tangjie(jie.tang@dfrobot.com), 2024. (Welcome to our [website](https://www.dfrobot.com/))
