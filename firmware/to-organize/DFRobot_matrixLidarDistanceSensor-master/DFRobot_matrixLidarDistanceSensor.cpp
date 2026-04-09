/*!
 * @file DFRobot_matrixLidarDistanceSensor.cpp
 * @brief This is the implementation file for DFRobot_matrixLidarDistanceSensor
 * @copyright   Copyright (c) 2024 DFRobot Co.Ltd (http://www.dfrobot.com)
 * @license     The MIT License (MIT)
 * @author [TangJie](jie.tang@dfrobot.com)
 * @version  V1.0
 * @date  2024-04-01
 * @url https://github.com/DFRobot/DFRobot_matrixLidarDistanceSensor
 */

#include "DFRobot_matrixLidarDistanceSensor.h"

#define CMD_SETMODE 1
#define CMD_ALLData 2
#define CMD_FIXED_POINT 3
#define CMD_LINE 4
#define CMD_LIST 5
#define CMD_AVOID_OBSTACLE 6
#define CMD_CONFIG_AVOID 7
#define CMD_OBSTACLE_DISTANCE 8

#define CMD_END             CMD_OBSTACLE_DISTANCE

#define STATUS_SUCCESS      0x53  ///< Status of successful response   
#define STATUS_FAILED       0x63  ///< Status of failed response 


#define IIC_MAX_TRANSFER            32     ///< Maximum transferred data via I2C
#define I2C_ACHE_MAX_LEN            32
#define DEBUG_TIMEOUT_MS 8000


#define ERR_CODE_NONE               0x00 ///< Normal communication 
#define ERR_CODE_CMD_INVAILED       0x01 ///< Invalid command
#define ERR_CODE_RES_PKT            0x02 ///< Response packet error
#define ERR_CODE_M_NO_SPACE         0x03 ///< Insufficient memory of I2C controller(master)
#define ERR_CODE_RES_TIMEOUT        0x04 ///< Response packet reception timeout
#define ERR_CODE_CMD_PKT            0x05 ///< Invalid command packet or unmatched command
#define ERR_CODE_SLAVE_BREAK        0x06 ///< Peripheral(slave) fault
#define ERR_CODE_ARGS               0x07 ///< Set wrong parameter
#define ERR_CODE_SKU                0x08 ///< The SKU is an invalid SKU, or unsupported by SCI Acquisition Module
#define ERR_CODE_S_NO_SPACE         0x09 ///< Insufficient memory of I2C peripheral(slave)
#define ERR_CODE_I2C_ADRESS         0x0A ///< Invalid I2C address

static uint8_t outDir = 0;
static uint8_t outEmergencyFlag = 0;
static uint16_t outLeft = 0;
static uint16_t outRight = 0;
static uint16_t outMiddle = 0;

typedef struct{
  uint8_t head;
  uint8_t argsNumH; /**< High byte of parameter number after the command    */
  uint8_t argsNumL; /**< Low byte of parameter number after the command    */
  uint8_t cmd;      /**< Command                     */
  uint8_t args[0];  /**< The array with 0-data length, its size depends on the value of the previous variables argsNumL and argsNumH     */
}__attribute__ ((packed)) sCmdSendPkt_t, *pCmdSendPkt_t;

typedef struct{
  uint8_t status;   /**< Response packet status, 0x53, response succeeded, 0x63, response failed */
  uint8_t cmd;      /**< Response packet command */
  uint8_t lenL;     /**< Low byte of the buf array length excluding packet header */
  uint8_t lenH;     /**< High byte of the buf array length excluding packet header */
  uint8_t buf[0];   /**< The array with 0-data length, its size depends on the value of the previous variables lenL and lenH */
}__attribute__ ((packed)) sCmdRecvPkt_t, *pCmdRecvPkt_t;

DFRobot_matrixLidarDistanceSensor::DFRobot_matrixLidarDistanceSensor(uint8_t addr, TwoWire *pWire):_pWire(pWire),_addr(addr),_timeout(DEBUG_TIMEOUT_MS){

}

uint8_t DFRobot_matrixLidarDistanceSensor::begin(void){
  _pWire->begin();
  _pWire->beginTransmission(_addr);
  if(_pWire->endTransmission()){
    return 1;
  }
  return 0;
}

uint8_t DFRobot_matrixLidarDistanceSensor::getAllDataConfig(eMatrix_t matrix){
  uint8_t length = 4;
  uint8_t errorCode;
  pCmdSendPkt_t sendpkt = NULL;
  sendpkt = (pCmdSendPkt_t)malloc(sizeof(sCmdSendPkt_t) + length);
  if(sendpkt == NULL) return 1;
  sendpkt->head = 0x55;
  sendpkt->argsNumH = ((length + 1) >> 8) & 0xFF;
  sendpkt->argsNumL = (length + 1) & 0xFF;
  sendpkt->cmd = CMD_SETMODE;
  sendpkt->args[0] = 0;
  sendpkt->args[1] = 0;
  sendpkt->args[2] = 0;
  sendpkt->args[3] = matrix;
  
  length += sizeof(sCmdSendPkt_t);
  DBG(length);
  sendPacket(sendpkt, length , true);
  free(sendpkt);
  pCmdRecvPkt_t rcvpkt = (pCmdRecvPkt_t)recvPacket(CMD_SETMODE, &errorCode);
  if((rcvpkt != NULL) && (rcvpkt->status == STATUS_FAILED)) errorCode = rcvpkt->buf[0];
  if((rcvpkt != NULL) && (rcvpkt->status == STATUS_SUCCESS)){
    length = (rcvpkt->lenH << 8) | rcvpkt->lenL;
    if(rcvpkt) free(rcvpkt);
    delay(5000);
    return 0;
  }
  return 1;
}

uint8_t DFRobot_matrixLidarDistanceSensor::configAvoidance(uint8_t wall){
  uint8_t length = 2;
  uint8_t errorCode;
  uint16_t _wall = wall * 10;
  pCmdSendPkt_t sendpkt = NULL;
  sendpkt = (pCmdSendPkt_t)malloc(sizeof(sCmdSendPkt_t) + length);
  if(sendpkt == NULL) return 1;
  sendpkt->head = 0x55;
  sendpkt->argsNumH = ((length + 1) >> 8) & 0xFF;
  sendpkt->argsNumL = (length + 1) & 0xFF;
  sendpkt->cmd = CMD_CONFIG_AVOID;
  sendpkt->args[0] = (_wall >> 8) & 0xff;
  sendpkt->args[1] = _wall & 0xff;
  
  length += sizeof(sCmdSendPkt_t);
  DBG(length);
  sendPacket(sendpkt, length , true);
  free(sendpkt);
  pCmdRecvPkt_t rcvpkt = (pCmdRecvPkt_t)recvPacket(CMD_CONFIG_AVOID, &errorCode);
  if((rcvpkt != NULL) && (rcvpkt->status == STATUS_FAILED)) errorCode = rcvpkt->buf[0];
  if((rcvpkt != NULL) && (rcvpkt->status == STATUS_SUCCESS)){
    length = (rcvpkt->lenH << 8) | rcvpkt->lenL;
    if(rcvpkt) free(rcvpkt);
    return 0;
  }
  return 1;
}

uint8_t DFRobot_matrixLidarDistanceSensor::getAllData(void *buf){
  uint8_t length = 0;
  uint8_t errorCode;
  pCmdSendPkt_t sendpkt = NULL;
  sendpkt = (pCmdSendPkt_t)malloc(sizeof(sCmdSendPkt_t) + length);
  if(sendpkt == NULL) return 1;
  sendpkt->head = 0x55;
  sendpkt->argsNumH = ((length + 1) >> 8) & 0xFF;
  sendpkt->argsNumL = (length + 1) & 0xFF;
  sendpkt->cmd = CMD_ALLData;
  
  length += sizeof(sCmdSendPkt_t);
  DBG(length);
  sendPacket(sendpkt, length , true);
  free(sendpkt);
  pCmdRecvPkt_t rcvpkt = (pCmdRecvPkt_t)recvPacket(CMD_ALLData, &errorCode);
  if((rcvpkt != NULL) && (rcvpkt->status == STATUS_FAILED)) errorCode = rcvpkt->buf[0];
  if((rcvpkt != NULL) && (rcvpkt->status == STATUS_SUCCESS)){
    length = (rcvpkt->lenH << 8) | rcvpkt->lenL;
    DBG(length);
    memcpy(buf,rcvpkt->buf,length);
    if(rcvpkt) free(rcvpkt);
    return 0;
  }
  return 1;
}

uint16_t DFRobot_matrixLidarDistanceSensor::getFixedPointData(uint8_t x, uint8_t y){
  uint8_t length = 2;
  uint16_t ret = 0;
  uint8_t errorCode;
  pCmdSendPkt_t sendpkt = NULL;
  sendpkt = (pCmdSendPkt_t)malloc(sizeof(sCmdSendPkt_t) + length);
  if(sendpkt == NULL) return 1;
  sendpkt->head = 0x55;
  sendpkt->argsNumH = ((length + 1) >> 8) & 0xFF;
  sendpkt->argsNumL = (length + 1) & 0xFF;
  sendpkt->cmd = CMD_FIXED_POINT;
  sendpkt->args[0] = x; 
  sendpkt->args[1] = y;
  
  length += sizeof(sCmdSendPkt_t);
  DBG(length);
  sendPacket(sendpkt, length , true);
  free(sendpkt);
  pCmdRecvPkt_t rcvpkt = (pCmdRecvPkt_t)recvPacket(CMD_FIXED_POINT, &errorCode);
  if((rcvpkt != NULL) && (rcvpkt->status == STATUS_FAILED)) errorCode = rcvpkt->buf[0];
  if((rcvpkt != NULL) && (rcvpkt->status == STATUS_SUCCESS)){
    length = (rcvpkt->lenH << 8) | rcvpkt->lenL;
    ret = rcvpkt->buf[1] << 8 | rcvpkt->buf[0];
    DBG(length);
    if(rcvpkt) free(rcvpkt);
    return ret;
  }
  return 1;
}

uint8_t DFRobot_matrixLidarDistanceSensor::requestObstacleSensorData(void){
  uint8_t length = 0;
  uint8_t errorCode;
  pCmdSendPkt_t sendpkt = NULL;
  sendpkt = (pCmdSendPkt_t)malloc(sizeof(sCmdSendPkt_t) + length);
  if(sendpkt == NULL) return 1;
  sendpkt->head = 0x55;
  sendpkt->argsNumH = ((length + 1) >> 8) & 0xFF;
  sendpkt->argsNumL = (length + 1) & 0xFF;
  sendpkt->cmd = CMD_AVOID_OBSTACLE;
  
  length += sizeof(sCmdSendPkt_t);
  DBG(length);
  sendPacket(sendpkt, length , true);
  free(sendpkt);
  pCmdRecvPkt_t rcvpkt = (pCmdRecvPkt_t)recvPacket(CMD_AVOID_OBSTACLE, &errorCode);
  if((rcvpkt != NULL) && (rcvpkt->status == STATUS_FAILED)) errorCode = rcvpkt->buf[0];
  if((rcvpkt != NULL) && (rcvpkt->status == STATUS_SUCCESS)){
    length = (rcvpkt->lenH << 8) | rcvpkt->lenL;
    DBG(length);
    outDir = rcvpkt->buf[0];
    outEmergencyFlag = rcvpkt->buf[1];
    //memcpy(buf,rcvpkt->buf,length);
    if(rcvpkt) free(rcvpkt);
    return 0;
  }
  return 1;
}

uint8_t DFRobot_matrixLidarDistanceSensor::getDir(void){
  return outDir;
}

uint8_t DFRobot_matrixLidarDistanceSensor::getEmergencyFlag(void){
  return outEmergencyFlag;
}

uint8_t DFRobot_matrixLidarDistanceSensor::requestObstacleDistance(void){
  uint8_t length = 0;
  uint8_t errorCode;
  pCmdSendPkt_t sendpkt = NULL;
  sendpkt = (pCmdSendPkt_t)malloc(sizeof(sCmdSendPkt_t) + length);
  if(sendpkt == NULL) return 1;
  sendpkt->head = 0x55;
  sendpkt->argsNumH = ((length + 1) >> 8) & 0xFF;
  sendpkt->argsNumL = (length + 1) & 0xFF;
  sendpkt->cmd = CMD_OBSTACLE_DISTANCE;
  
  length += sizeof(sCmdSendPkt_t);
  DBG(length);
  sendPacket(sendpkt, length , true);
  free(sendpkt);
  pCmdRecvPkt_t rcvpkt = (pCmdRecvPkt_t)recvPacket(CMD_OBSTACLE_DISTANCE, &errorCode);
  if((rcvpkt != NULL) && (rcvpkt->status == STATUS_FAILED)) errorCode = rcvpkt->buf[0];
  if((rcvpkt != NULL) && (rcvpkt->status == STATUS_SUCCESS)){
    length = (rcvpkt->lenH << 8) | rcvpkt->lenL;
    DBG(length);
    outLeft = (rcvpkt->buf[0] | rcvpkt->buf[1] << 8) / 10;
    outMiddle = (rcvpkt->buf[2] | rcvpkt->buf[3] << 8) / 10;
    outRight = (rcvpkt->buf[4] | rcvpkt->buf[5] << 8) / 10;
    if(rcvpkt) free(rcvpkt);
    return 0;
  }
  return 1;

}

uint16_t DFRobot_matrixLidarDistanceSensor::getDistance(eDir_t dir){
  uint16_t _ret = 0;
  switch(dir){
    case eLeft:
      _ret = outLeft;
    break;
    case eMiddle:
    _ret = outMiddle;
    break;
    case eRight:
    _ret = outRight;
    break;
    default:
    break;
  }
  return _ret;
}


void DFRobot_matrixLidarDistanceSensor::sendPacket(void *pkt, int length, bool stop){
  uint8_t *pBuf = (uint8_t *)pkt;
  int remain = length;
  if((pkt == NULL) || (length == 0)) return;
  _pWire->beginTransmission(_addr);
  while(remain){
     DBG("a");
    length = (remain > IIC_MAX_TRANSFER) ? IIC_MAX_TRANSFER : remain;
    _pWire->write(pBuf, length);
    remain -= length;
    pBuf += length;
#if defined(ESP32)
    if(remain) _pWire->endTransmission(true);
#else
    if(remain) _pWire->endTransmission(false);
#endif
  }
  _pWire->endTransmission();
}


void * DFRobot_matrixLidarDistanceSensor::recvPacket(uint8_t cmd, uint8_t *errorCode){
  if(cmd > CMD_END){
    DBG("cmd is error!");
    if(errorCode) *errorCode = ERR_CODE_CMD_INVAILED; //There is no this command
    return NULL;
  }
  
  sCmdRecvPkt_t recvPkt;
  pCmdRecvPkt_t recvPktPtr = NULL;
  uint16_t length = 0;
  uint32_t t = millis();
  while(millis() - t < _timeout/*time_ms*/){
    DBG("k");
    recvData(&recvPkt.status, 1);
    if(recvPkt.status != 0xff){
      switch(recvPkt.status){
        case STATUS_SUCCESS:
        case STATUS_FAILED:{
          recvData(&recvPkt.cmd, 1);
          if(recvPkt.cmd != cmd){
            //recvFlush();
            if(errorCode) *errorCode = ERR_CODE_RES_PKT; //Response packet error
            DBG("Response pkt is error!");
            return NULL;
          }
          recvData(&recvPkt.lenL, 2);
          length = (recvPkt.lenH << 8) | recvPkt.lenL;
          if(length<1000){
            recvPktPtr = (pCmdRecvPkt_t)malloc(sizeof(sCmdRecvPkt_t) + length);
          }else{
             return NULL;
           }
          
          if(recvPktPtr == NULL){
            if(errorCode) *errorCode = ERR_CODE_M_NO_SPACE; //Insufficient memory of I2C controller(master)
            DBG("malloc error");
            free(recvPktPtr);
            return NULL;
          }
          memcpy(recvPktPtr, &recvPkt, sizeof(sCmdRecvPkt_t));
      
          if(length)recvData(recvPktPtr->buf, length);
          if(errorCode) *errorCode = ERR_CODE_NONE;
          return recvPktPtr;
      }
      default:
        //restData();
        delay(10);
        break;
    }
    }
    
    delay(17);
  }
  if(errorCode) *errorCode = ERR_CODE_RES_TIMEOUT; //Receive packet timeout
  free(recvPktPtr);
  DBG("Time out!");
  DBG(millis() - t);
  return NULL;
}

int DFRobot_matrixLidarDistanceSensor::recvData(void *data, int len){
  uint8_t *pBuf = (uint8_t *)data;
  int remain = len;
  int total = 0;
  if(pBuf == NULL){
    DBG("pBuf ERROR!! : null pointer");
    return 0;
  }
  while(remain){
    len = remain > I2C_ACHE_MAX_LEN ? I2C_ACHE_MAX_LEN : remain;
    remain -= len;
#if defined(ESP32)
    if(remain) {_pWire->requestFrom(_addr, len, true);}
#else
    if(remain){ _pWire->requestFrom(_addr, len, false);}
#endif
  else{_pWire->requestFrom(_addr, len, true);}
    for(int i = 0; i < len; i++){
      pBuf[i] = _pWire->read();
      yield();
    }
    pBuf += len;
    total += len;
  }
  return total;
}


