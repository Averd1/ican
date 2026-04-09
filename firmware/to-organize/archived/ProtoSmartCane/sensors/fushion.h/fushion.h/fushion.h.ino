#pragma once


enum Situation{
  NONE,
  OBJECT_FAR,
  OBJECT_NEAR,
  OBJECT_IMMINENT,
  FALL_DETECTED,
  LOW_LIGHT,
  HIGH_STRESS
};

extern Situation currentSituation;

void fuseSituations();
