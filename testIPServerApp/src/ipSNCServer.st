program ipSNCServer("P=testIPServer:=, PORT=P5000")

option +r;

%%#include <string.h>
%%#include <epicsString.h>
%%#include <epicsEvent.h>
%%#include <asynDriver.h>
%%#include <asynOctet.h>
%%#include <asynOctetSyncIO.h>
%%#include <asynCommonSyncIO.h>

#define BUFFER_SIZE 80

string input;  assign input     to "{P}stringInput";
string output; assign output    to "{P}stringOutput";
int connected; assign connected to "{P}connected";

char *listenerPortName;
char *IOPortName;
int readStatus;
int writeStatus;
char *pasynUser;    /* This is really asynUser* */
char *registrarPvt; /* This is really void* */
char *eventId;      /* Thus is really epicsEventId */

/* Define escaped C functions at end of file */
%% static void initialize(SS_ID ssId, struct UserVar *pVar);
%% static int readSocket(SS_ID ssId, struct UserVar *pVar);
%% static int writeSocket(SS_ID ssId, struct UserVar *pVar);

ss ipSNCServer
{
    state init {
        when() {
            listenerPortName = macValueGet("PORT");
            %%initialize(ssId, pVar);
            connected = 0;
        } state waitConnect
    }

    state waitConnect {
        when() {
            pvPut(connected);
            %%epicsEventWait( (epicsEventId)pVar->eventId);
            pvPut(connected);
        } state processCommands
    }

    state processCommands {
        when(connected) {
            %%pVar->readStatus = readSocket(ssId, pVar);
            if (readStatus == 0) {
                pvPut(input);
                strcpy(output, "OK");
                %%pVar->writeStatus = writeSocket(ssId, pVar);
                if (writeStatus == 0) {
                    pvPut(output);
                }
            }
        } state processCommands

        when(!connected) {
        } state waitConnect
 
    }
}

%{
static void connectionCallback(void *drvPvt, asynUser *pasynUserIn, char *portName, size_t len, int eomReason)
{
    struct UserVar  *pVar = (struct UserVar *)drvPvt;
    asynUser *pasynUser = (asynUser *)pVar->pasynUser;
    asynStatus status;

    pVar->IOPortName = epicsStrDup(portName);
    asynPrint(pasynUser, ASYN_TRACE_FLOW,
              "ipSNCServer: connectionCallback, portName=%s\n", portName);
    status = pasynOctetSyncIO->connect(portName, 0, (asynUser **)&pVar->pasynUser, NULL);
    pasynUser = (asynUser *)pVar->pasynUser;
    if (status) {
        asynPrint(pasynUser, ASYN_TRACE_ERROR,
                  "ipSNCServer:connectionCallback: unable to connect to port %s\n",
                  portName);
        return;
    }
    status = pasynOctetSyncIO->setInputEos(pasynUser, "\r\n", 2);
    if (status) {
        asynPrint(pasynUser, ASYN_TRACE_ERROR,
                  "ipSNCServer:connectionCallback: unable to set input EOS on %s: %s\n",
                  portName, pasynUser->errorMessage);
        return;
    }
    status = pasynOctetSyncIO->setOutputEos(pasynUser, "\r\n", 2);
    if (status) {
        asynPrint(pasynUser, ASYN_TRACE_ERROR,
                  "ipSNCServer:connectionCallback: unable to set output EOS on %s: %s\n",
                  portName, pasynUser->errorMessage);
        return;
    }
    /* Connect pasynUser to asynCommon interface */
    status = pasynCommonSyncIO->connect(portName, 0, &pasynUser, NULL);
    if (status) {
        asynPrint(pasynUser, ASYN_TRACE_ERROR,
                  "ipSNCServer:connectionCallback: error connecting to asynCommon interface error on: %s\n",
                  portName);
    }
    /* Send an EPICS event to wake up the SNL program */
    pVar->connected = 1;
    epicsEventSignal( (epicsEventId)pVar->eventId);
}

static void initialize(SS_ID ssId, struct UserVar *pVar)
{
    int addr=0;
    asynInterface *pasynInterface;
    asynUser *pasynUser;
    asynOctet *pasynOctet;
    int status;

    pVar->eventId = (char *)epicsEventCreate(epicsEventEmpty);
    pasynUser = pasynManager->createAsynUser(0,0);
    pVar->pasynUser = (char *)pasynUser;
    pasynUser->userPvt = pVar;
    status = pasynManager->connectDevice(pasynUser, pVar->listenerPortName, addr);
    if(status!=asynSuccess) {
        printf("can't connect to port %s: %s\n", pVar->listenerPortName, pasynUser->errorMessage);
        return;
    }
    pasynInterface = pasynManager->findInterface(pasynUser,asynOctetType,1);
    if(!pasynInterface) {
        printf("%s driver not supported\n",asynOctetType);
        return;
    }
    pasynOctet = (asynOctet *)pasynInterface->pinterface;
    status = pasynOctet->registerInterruptUser(
                 pasynInterface->drvPvt, pasynUser,
                 connectionCallback,pVar,(void **)&pVar->registrarPvt);
    if(status!=asynSuccess) {
        printf("ipSNCServer devAsynOctet registerInterruptUser %s\n",
               pasynUser->errorMessage);
    }
}

static int readSocket(SS_ID ssId, struct UserVar *pVar)
{
    char buffer[BUFFER_SIZE];
    int nread, eomReason;
    asynUser *pasynUser = (asynUser *)pVar->pasynUser;
    asynStatus status, readStatus;

    readStatus = pasynOctetSyncIO->read(pasynUser, buffer, BUFFER_SIZE,
                                    0.0, &nread, &eomReason);
    if (readStatus) {
        asynPrint(pasynUser, ASYN_TRACE_ERROR,
                  "echoHandler: read error on: %s: %s\n",
                  pVar->IOPortName, pasynUser->errorMessage);
        /* Disconnect from device */
        status = pasynCommonSyncIO->disconnectDevice(pasynUser);
        if (status) {
            asynPrint(pasynUser, ASYN_TRACE_ERROR,
                      "ipSNCServer:readSocket: disconnect device error on: %s: %s\n",
                      pVar->IOPortName, pasynUser->errorMessage);
        }
        pVar->connected = 0;
    }
    else asynPrint(pasynUser, ASYN_TRACEIO_DEVICE,
                   "echoHandler: %s read %s: %s: %s\n",
                   pVar->IOPortName, buffer);
    strcpy(pVar->input, buffer);
    return(readStatus);
}

static int writeSocket(SS_ID ssId, struct UserVar *pVar)
{
    int nwrite;
    asynUser *pasynUser = (asynUser *)pVar->pasynUser;
    asynStatus status, writeStatus;

    writeStatus = pasynOctetSyncIO->write(pasynUser, pVar->output, strlen(pVar->output),
                                    0.0, &nwrite);
    if (writeStatus) {
        asynPrint(pasynUser, ASYN_TRACE_ERROR,
                  "ipSNCServer:writeSocket: write error on: %s: %s\n",
                  pVar->IOPortName, pasynUser->errorMessage);
        /* Disconnect from device */
        status = pasynCommonSyncIO->disconnectDevice(pasynUser);
        if (status) {
            asynPrint(pasynUser, ASYN_TRACE_ERROR,
                      "ipSNCServer:writeSocket: disconnect device error on: %s: %s\n",
                      pVar->IOPortName, pasynUser->errorMessage);
        }
        pVar->connected = 0;
    }
    else asynPrint(pasynUser, ASYN_TRACEIO_DEVICE,
                   "ipSNCServer:writeSocket: %s write %s\n",
                   pVar->IOPortName, pVar->output);
    return(writeStatus);
}

}%