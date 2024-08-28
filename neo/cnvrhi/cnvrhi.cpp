#include "./cnvrhi.h"

void c_nvrhi_device_waitForIdle(nvrhi::IDevice* device) {
	device->waitForIdle();
}

void c_nvrhi_device_executeCommandList(nvrhi::IDevice* device, nvrhi::ICommandList* commandList) {
	device->executeCommandList(commandList);
}

void c_nvrhi_device_createCommandList(nvrhi::IDevice* device, nvrhi::CommandListHandle* handle, nvrhi::CommandListParameters params) {
	*handle = device->createCommandList(params);
}

void c_nvrhi_device_runGarbageCollection(nvrhi::IDevice* device) {
	device->runGarbageCollection();
}

void c_nvrhi_commandList_open(nvrhi::ICommandList* commandList) {
	commandList->open();
}

void c_nvrhi_commandList_close(nvrhi::ICommandList* commandList) {
	commandList->close();
}

unsigned long c_nvrhi_resource_addRef(nvrhi::IResource* res) {
	return res->AddRef();
}

unsigned long c_nvrhi_resource_release(nvrhi::IResource* res) {
	return res->Release();
}
