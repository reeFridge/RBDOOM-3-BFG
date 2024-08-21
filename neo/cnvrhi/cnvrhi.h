#pragma once

#include "nvrhi/nvrhi.h"

extern "C" {

void c_nvrhi_device_waitForIdle(nvrhi::IDevice* device);
void c_nvrhi_device_executeCommandList(nvrhi::IDevice* device, nvrhi::ICommandList* commandList);
void c_nvrhi_device_createCommandList(nvrhi::IDevice* device, nvrhi::CommandListHandle* handle);
void c_nvrhi_commandList_open(nvrhi::ICommandList* commandList);
void c_nvrhi_commandList_close(nvrhi::ICommandList* commandList);
unsigned long c_nvrhi_resource_addRef(nvrhi::IResource* res);
unsigned long c_nvrhi_resource_release(nvrhi::IResource* res);

}
