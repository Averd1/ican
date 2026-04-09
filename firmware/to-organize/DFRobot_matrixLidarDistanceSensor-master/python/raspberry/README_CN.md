# DFRobot_matrixLidarDistanceSensor
- [English Version](./README.md)

这是一个获取TOF原始数据和避障建议的用户库。

![](./resources/images/SEN0628.png)

## 产品链接(https://www.dfrobot.com.cn)

    SKU：SEN0628

## 目录

* [概述](#概述)
* [库安装](#库安装)
* [方法](#方法)
* [兼容性](#兼容性y)
* [历史](#历史)
* [创作者](#创作者)

## 概述
  一个获取TOF原始数据和避障建议的用户库。

## 库安装

使用此库前，请首先下载库文件，将其粘贴到\Arduino\libraries目录中，然后打开examples文件夹并在该文件夹中运行演示。

## 方法

```python
	def begin(self)
		'''!
			@fn begin
			@brief 初始化传感器
			@return 返回初始化状态
		'''
  
	def get_all_data_config(self, matrix)
		'''!
			@fn get_all_data_config
			@brief 获取全部数据的配置
			@param matrix 配置传感器采样矩阵
			@return 返回配置状态
			@retval 0 成功
			@retval 1 失败
		'''
  
	def config_avoidance(self, wall)
		'''!
    		@fn   config_avoidance
    		@brief 初始化避障
    		@param wall 配置避障距离，单位：厘米
    	'''
      
	def get_all_data(self)
		'''!
      		@fn get_all_data
      		@brief 获取全部数据
      		@return 返回获取的数据
    	'''
    
	def get_fixed_point_data(self, x, y)
		'''!
			@fn get_fixed_point_data
      		@brief 获取指定桌标的数据
      		@param x 坐标X
      		@param y 坐标y
      		@return 返回获取的数据
    	'''
    
	def request_obstacle_sensor_data(self)
		'''!
			@fn request_obstacle_sensor_data
      		@brief 请求避障数据
      		@return 返回获取状态
    	'''
    
	def get_dir(self)
		'''!
      		@fn get_dir
      		@brief 获取避障方向建议
      		@return 返回避障方向建议
    	'''
    
	def get_emergency_flag(self)
		'''!
      		@fn get_emergency_flag
      		@brief 获取紧急避障标志
      		@return 返回避障标志
    	'''
    
	def request_obstacle_distance(self)
		'''!
			@fn request_obstacle_distance
      		@brief 请求障碍物距离
      		@return 返回请求状态
    	'''
    
	def get_diatance(self,dir)
		'''!
			@fn get_diatance
      		@brief 获取距离数据
     		@param dir 方向
      		@return 返回获取的方向
    	'''
  
```

## 兼容性

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


## 历史

- 2024-09-9 - 1.0.0 版本

## 创作者

Written by TangJie(jie.tang@dfrobot.com), 2024. (Welcome to our [website](https://www.dfrobot.com/))





