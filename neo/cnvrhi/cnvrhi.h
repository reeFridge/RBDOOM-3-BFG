#pragma once

#include "nvrhi/vulkan.h"
#include "nvrhi/nvrhi.h"
#include "nvrhi/utils.h"

#define VULKAN_HPP_DISPATCH_LOADER_DYNAMIC 1
#include <vulkan/vulkan.hpp>

extern "C" {

void c_nvrhi_device_waitForIdle(nvrhi::IDevice* device);
void c_nvrhi_device_executeCommandList(
		nvrhi::IDevice* device,
		nvrhi::ICommandList* commandList);
void c_nvrhi_device_createHandleForNativeTexture(
		nvrhi::IDevice* device,
		nvrhi::TextureHandle* handle,
		nvrhi::ObjectType objectType,
		nvrhi::Object object,
		const nvrhi::TextureDesc* desc);
void c_nvrhi_device_createHandleForNativeBuffer(
		nvrhi::IDevice* device,
		nvrhi::BufferHandle* handle,
		nvrhi::ObjectType objectType,
		nvrhi::Object buffer,
		const nvrhi::BufferDesc* desc);
void c_nvrhi_device_createEventQuery(
		nvrhi::IDevice* device,
		nvrhi::EventQueryHandle* handle);
void c_nvrhi_device_setEventQuery(
		nvrhi::IDevice* device,
		nvrhi::IEventQuery* query,
		nvrhi::CommandQueue queue);
void c_nvrhi_device_createCommandList(
		nvrhi::IDevice* device,
		nvrhi::CommandListHandle* handle,
		nvrhi::CommandListParameters);
void c_nvrhi_device_createBuffer(
		nvrhi::IDevice* device,
		nvrhi::BufferHandle* handle,
		const nvrhi::BufferDesc* desc);
void c_nvrhi_device_createFramebuffer(
		nvrhi::IDevice* device,
		nvrhi::FramebufferHandle* handle,
		const nvrhi::FramebufferDesc* desc);
void c_nvrhi_device_createSampler(
		nvrhi::IDevice* device,
		nvrhi::SamplerHandle* handle,
		const nvrhi::SamplerDesc* desc);
void c_nvrhi_device_createTexture(
		nvrhi::IDevice* device,
		nvrhi::TextureHandle* handle,
		const nvrhi::TextureDesc* desc);
void c_nvrhi_device_createShader(
		nvrhi::IDevice* device,
		nvrhi::ShaderHandle* handle,
		const nvrhi::ShaderDesc* desc,
		const void* binary,
		size_t binarySize);
void c_nvrhi_device_createBindingLayout(
		nvrhi::IDevice* device,
		nvrhi::BindingLayoutHandle* handle,
		const nvrhi::BindingLayoutDesc* desc);
void c_nvrhi_device_createInputLayout(
		nvrhi::IDevice* device,
		nvrhi::InputLayoutHandle* handle,
		const nvrhi::VertexAttributeDesc* descs,
		uint32_t attributeCount,
		nvrhi::IShader* vertexShader);
void c_nvrhi_device_createBindingSet(
		nvrhi::IDevice* device,
		nvrhi::BindingSetHandle* handle,
		const nvrhi::BindingSetDesc* desc,
		nvrhi::IBindingLayout* layout);
void c_nvrhi_device_createGraphicsPipeline(
		nvrhi::IDevice* device,
		nvrhi::GraphicsPipelineHandle* handle,
		const nvrhi::GraphicsPipelineDesc* desc,
		nvrhi::IFramebuffer* framebuffer);

void c_nvrhi_device_runGarbageCollection(nvrhi::IDevice* device);

void c_nvrhi_commandList_open(nvrhi::ICommandList* commandList);
void c_nvrhi_commandList_close(nvrhi::ICommandList* commandList);
void c_nvrhi_commandList_clearDepthStencilTexture(
		nvrhi::ICommandList* commandList,
		nvrhi::ITexture* t,
		nvrhi::TextureSubresourceSet subresources,
		bool clearDepth,
		float depth,
		bool clearStencil,
		uint8_t stencil);
void c_nvrhi_commandList_beginTrackingTextureState(
		nvrhi::ICommandList* commandList,
		nvrhi::ITexture* texture,
		nvrhi::TextureSubresourceSet subresources,
		nvrhi::ResourceStates stateBits);
void c_nvrhi_commandList_writeTexture(
		nvrhi::ICommandList* commandList,
		nvrhi::ITexture* dest,
		uint32_t arraySlice,
		uint32_t mipLevel,
		const void* data,
		size_t rowPitch,
		size_t depthPitch);
void c_nvrhi_commandList_setPermanentTextureState(
		nvrhi::ICommandList* commandList,
		nvrhi::ITexture* texture,
		nvrhi::ResourceStates stateBits);
void c_nvrhi_commandList_beginTrackingBufferState(
		nvrhi::ICommandList* commandList,
		nvrhi::IBuffer* buffer,
		nvrhi::ResourceStates stateBits);
void c_nvrhi_commandList_writeBuffer(
		nvrhi::ICommandList* commandList,
		nvrhi::IBuffer* b,
		const void* data,
		size_t dataSize,
		uint64_t destOffsetBytes);
void c_nvrhi_commandList_setPermanentBufferState(
		nvrhi::ICommandList* commandList,
		nvrhi::IBuffer* buffer,
		nvrhi::ResourceStates stateBits);
void c_nvrhi_commandList_commitBarriers(nvrhi::ICommandList* commandList);
void c_nvrhi_commandList_draw(nvrhi::ICommandList* commandList, const nvrhi::DrawArguments* args);
void c_nvrhi_commandList_setPushConstants(
		nvrhi::ICommandList* commandList,
		const void* data,
		size_t byteSize);
void c_nvrhi_commandList_setGraphicsState(
		nvrhi::ICommandList* commandList,
		const nvrhi::GraphicsState* state);

const nvrhi::TextureDesc* c_nvrhi_texture_getDesc(const nvrhi::ITexture* texture);

const nvrhi::BindingSetDesc* c_nvrhi_bindingSet_getDesc(const nvrhi::IBindingSet* set);
bool c_nvrhi_bindingSetDesc_eql(
		const nvrhi::BindingSetDesc* a,
		const nvrhi::BindingSetDesc* b);
void c_nvrhi_bindingSetDesc_hashCombine(const nvrhi::BindingSetDesc* desc, size_t* seed);

void c_nvrhi_hashCombinePtr(size_t* seed, void* ptr);

const nvrhi::FramebufferInfoEx* c_nvrhi_framebuffer_getFramebufferInfo(
		const nvrhi::IFramebuffer* framebuffer);

const nvrhi::FramebufferDesc* c_nvrhi_framebuffer_getDesc(
		const nvrhi::IFramebuffer* framebuffer);

unsigned long c_nvrhi_resource_addRef(nvrhi::IResource* res);
unsigned long c_nvrhi_resource_release(nvrhi::IResource* res);

void c_nvrhi_vertexAttributeDesc_setName(nvrhi::VertexAttributeDesc*, const char*);
const char* c_nvrhi_vertexAttributeDesc_getName(const nvrhi::VertexAttributeDesc*);

const nvrhi::FormatInfo* c_nvrhi_getFormatInfo(nvrhi::Format);

// vulkan

VkFormat c_nvrhi_vulkan_convertFormat(nvrhi::Format format);
void c_nvrhi_vulkan_createDevice(
		const nvrhi::vulkan::DeviceDesc* desc,
		nvrhi::DeviceHandle* handle,
		PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr);

void c_nvrhi_vulkan_device_queueSignalSemaphore(
		nvrhi::vulkan::IDevice* device,
		nvrhi::CommandQueue executionQueue,
		VkSemaphore semaphore,
		uint64_t value);
void c_nvrhi_vulkan_device_queueWaitForSemaphore(
		nvrhi::vulkan::IDevice* device,
		nvrhi::CommandQueue waitQueue,
		VkSemaphore semaphore,
		uint64_t value);

// utils

nvrhi::BufferDesc c_nvrhi_utils_createVolatileConstantBufferDesc(
		uint32_t byteSize,
		const char* debugName,
		uint32_t maxVersions);

void c_nvrhi_utils_clearColorAttachment(
		nvrhi::ICommandList* commandList,
		nvrhi::IFramebuffer* framebuffer,
		uint32_t attachmentIndex,
		nvrhi::Color color);

}
