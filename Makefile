#Makefile at top of application tree
TOP = .
include $(TOP)/configure/CONFIG
DIRS += configure
DIRS += makeSupport
DIRS += asyn
DIRS += testManagerApp
DIRS += testApp
DIRS += testGpibApp
DIRS += testGpibSerialApp
DIRS += testEpicsApp
DIRS += iocBoot
include $(TOP)/configure/RULES_TOP
