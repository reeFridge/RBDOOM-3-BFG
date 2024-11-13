#include "./cnvrhi.h"

void c_nvrhi_device_waitForIdle(nvrhi::IDevice* device) {
	device->waitForIdle();
}

void c_nvrhi_device_executeCommandList(
		nvrhi::IDevice* device,
		nvrhi::ICommandList* commandList)
{
	device->executeCommandList(commandList);
}

void c_nvrhi_device_createHandleForNativeTexture(
		nvrhi::IDevice* device,
		nvrhi::TextureHandle* handle,
        nvrhi::ObjectType objectType,
        nvrhi::Object object,
        const nvrhi::TextureDesc* desc
		)
{
	*handle = device->createHandleForNativeTexture(objectType, object, *desc);
}

void c_nvrhi_device_createCommandList(
		nvrhi::IDevice* device,
		nvrhi::CommandListHandle* handle,
		nvrhi::CommandListParameters params)
{
	*handle = device->createCommandList(params);
}

void c_nvrhi_device_createBuffer(
		nvrhi::IDevice* device,
		nvrhi::BufferHandle* handle,
		const nvrhi::BufferDesc* desc)
{
	*handle = device->createBuffer(*desc);
}

void c_nvrhi_device_createBindingLayout(
		nvrhi::IDevice* device,
		nvrhi::BindingLayoutHandle* handle,
		const nvrhi::BindingLayoutDesc* desc)
{
	*handle = device->createBindingLayout(*desc);
}

void c_nvrhi_device_createShader(
		nvrhi::IDevice* device,
		nvrhi::ShaderHandle* handle,
		const nvrhi::ShaderDesc* desc,
		const void* binary,
		size_t binarySize)
{
	*handle = device->createShader(*desc, binary, binarySize);
}


void c_nvrhi_device_createInputLayout(
		nvrhi::IDevice* device,
		nvrhi::InputLayoutHandle* handle,
		const nvrhi::VertexAttributeDesc* descs,
		uint32_t attributeCount,
		nvrhi::IShader* vertexShader)
{
	*handle = device->createInputLayout(descs, attributeCount, vertexShader);
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

void c_nvrhi_commandList_writeTexture(
		nvrhi::ICommandList* commandList,
		nvrhi::ITexture* dest,
		uint32_t arraySlice,
		uint32_t mipLevel,
		const void* data,
		size_t rowPitch,
		size_t depthPitch)
{
	commandList->writeTexture(dest, arraySlice, mipLevel, data, rowPitch, depthPitch);
}

void c_nvrhi_commandList_setPermanentTextureState(
		nvrhi::ICommandList* commandList,
		nvrhi::ITexture* texture,
		nvrhi::ResourceStates stateBits)
{
	commandList->setPermanentTextureState(texture, stateBits);
}

void c_nvrhi_commandList_commitBarriers(nvrhi::ICommandList* commandList) {
	commandList->commitBarriers();
}

void c_nvrhi_commandList_beginTrackingTextureState(
		nvrhi::ICommandList* commandList,
		nvrhi::ITexture* texture,
		nvrhi::TextureSubresourceSet subresources,
		nvrhi::ResourceStates stateBits)
{
	commandList->beginTrackingTextureState(texture, subresources, stateBits);
}

unsigned long c_nvrhi_resource_addRef(nvrhi::IResource* res) {
	return res->AddRef();
}

unsigned long c_nvrhi_resource_release(nvrhi::IResource* res) {
	return res->Release();
}

void c_nvrhi_vertexAttributeDesc_setName(
		nvrhi::VertexAttributeDesc* desc,
		const char* name)
{
	desc->setName(name);
}

const char* c_nvrhi_vertexAttributeDesc_getName(const nvrhi::VertexAttributeDesc* desc) {
	return desc->name.c_str();
}

const nvrhi::FormatInfo* c_nvrhi_getFormatInfo(nvrhi::Format format) {
	return &nvrhi::getFormatInfo(format);
}

// vulkan

VkFormat c_nvrhi_vulkan_convertFormat(nvrhi::Format format) {
	return nvrhi::vulkan::convertFormat(format);
}

// utils

nvrhi::BufferDesc c_nvrhi_utils_createVolatileConstantBufferDesc(
		uint32_t byteSize,
		const char* debugName,
		uint32_t maxVersions)
{
	return nvrhi::utils::CreateVolatileConstantBufferDesc(byteSize, debugName, maxVersions);

}
