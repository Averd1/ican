# DFRobot_matrixLidarDistanceSensor
- [中文版](./README_CN.md)

This is a user library for retrieving TOF sensor raw data and providing obstacle avoidance suggestions.

![](./resources/images/SEN0628.png)

## Product link(https://www.dfrobot.com)

    SKU：SEN0628

## 目录

* [Overview](#Overview)
* [installation](#installation)
* [Methods](#Methods)
* [compatibility](#compatibility)
* [history](#history)
* [credits](#credits)

## Overview
This is a user library for retrieving TOF sensor raw data and providing obstacle avoidance suggestions.

## installation

Before using this library, first download the library files, paste them into the \Arduino\libraries directory, then open the examples folder and run the examples within that folder.

## Methods

```python
    def begin(self)
        '''!
            @fn begin
            @brief Initialize the sensor
            @return Returns the initialization status
        '''
  
    def get_all_data_config(self, matrix)
        '''!
            @fn get_all_data_config
            @brief Configure the retrieval of all data
            @param matrix Configuration matrix for sensor sampling
            @return Returns the configuration status
            @retval 0 Success
            @retval 1 Failure
        '''
  
    def config_avoidance(self, wall)
        '''!
            @fn   config_avoidance
            @brief Initialize obstacle avoidance
            @param wall Configures the obstacle avoidance distance, in centimeters
        '''
      
    def get_all_data(self)
        '''!
            @fn get_all_data
            @brief Retrieve all data
            @return Returns the retrieved data
        '''
    
    def get_fixed_point_data(self, x, y)
        '''!
            @fn get_fixed_point_data
            @brief Retrieve data for a specific coordinate
            @param x X coordinate
            @param y Y coordinate
            @return Returns the retrieved data
        '''
    
    def request_obstacle_sensor_data(self)
        '''!
            @fn request_obstacle_sensor_data
            @brief Request obstacle sensor data
            @return Returns the retrieval status
        '''
    
    def get_dir(self)
        '''!
            @fn get_dir
            @brief Retrieve obstacle avoidance direction suggestions
            @return Returns the obstacle avoidance direction suggestions
        '''
    
    def get_emergency_flag(self)
        '''!
            @fn get_emergency_flag
            @brief Retrieve the emergency obstacle avoidance flag
            @return Returns the obstacle avoidance flag
        '''
    
    def request_obstacle_distance(self)
        '''!
            @fn request_obstacle_distance
            @brief Request the distance to obstacles
            @return Returns the request status
        '''
    
    def get_distance(self, dir)
        '''!
            @fn get_distance
            @brief Retrieve distance data
            @param dir Direction
            @return Returns the retrieved distance
        '''
  

  
```

## compatibility

* RaspberryPi Version

| Board        | Work Well | Work Wrong | Untested | Remarks |
| ------------ | :-------: | :--------: | :------: | ------- |
| RaspberryPi2 |           |            |    √     |         |
| RaspberryPi3 |     √     |            |          |         |
| RaspberryPi4 |           |            |     √    |         |

* Python Version

| Python  | Work Well | Work Wrong | Untested | Remarks |
| ------- | :-------: | :--------: | :------: | ------- |
| Python2 |           |            |    √     |         |
| Python3 |     √     |            |          |         |


## history

- 2024-09-9 - Version 1.0.0 released.

## credits

Written by TangJie(jie.tang@dfrobot.com), 2024. (Welcome to our [website](https://www.dfrobot.com/))





