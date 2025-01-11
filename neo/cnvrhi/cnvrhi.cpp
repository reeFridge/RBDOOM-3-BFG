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
		const nvrhi::TextureDesc* desc)
{
	const nvrhi::TextureDesc desc_copy = *desc;
	*handle = device->createHandleForNativeTexture(objectType, object, desc_copy);
}

void c_nvrhi_device_createHandleForNativeBuffer(
		nvrhi::IDevice* device,
		nvrhi::BufferHandle* handle,
		nvrhi::ObjectType objectType,
		nvrhi::Object buffer,
		const nvrhi::BufferDesc* desc)
{
	*handle = device->createHandleForNativeBuffer(objectType, buffer, *desc);
}

void c_nvrhi_device_createEventQuery(
		nvrhi::IDevice* device,
		nvrhi::EventQueryHandle* handle)
{
	*handle = device->createEventQuery();
}

void c_nvrhi_device_setEventQuery(
		nvrhi::IDevice* device,
		nvrhi::IEventQuery* query,
		nvrhi::CommandQueue queue)
{
	device->setEventQuery(query, queue);
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

void c_nvrhi_device_createFramebuffer(
		nvrhi::IDevice* device,
		nvrhi::FramebufferHandle* handle,
		const nvrhi::FramebufferDesc* desc)
{
	*handle = device->createFramebuffer(*desc);
}

void c_nvrhi_device_createSampler(
		nvrhi::IDevice* device,
		nvrhi::SamplerHandle* handle,
		const nvrhi::SamplerDesc* desc)
{
	*handle = device->createSampler(*desc);
}

void c_nvrhi_device_createTexture(
		nvrhi::IDevice* device,
		nvrhi::TextureHandle* handle,
		const nvrhi::TextureDesc* desc)
{
	*handle = device->createTexture(*desc);
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

void c_nvrhi_device_createBindingSet(
		nvrhi::IDevice* device,
		nvrhi::BindingSetHandle* handle,
		const nvrhi::BindingSetDesc* desc,
		nvrhi::IBindingLayout* layout)
{
	*handle = device->createBindingSet(*desc, layout);
}

void c_nvrhi_device_createGraphicsPipeline(
		nvrhi::IDevice* device,
		nvrhi::GraphicsPipelineHandle* handle,
		const nvrhi::GraphicsPipelineDesc* desc,
		nvrhi::IFramebuffer* framebuffer)
{
	*handle = device->createGraphicsPipeline(*desc, framebuffer);
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

void c_nvrhi_commandList_clearDepthStencilTexture(
		nvrhi::ICommandList* commandList,
		nvrhi::ITexture* t,
		nvrhi::TextureSubresourceSet subresources,
		bool clearDepth,
		float depth,
		bool clearStencil,
		uint8_t stencil)
{
	commandList->clearDepthStencilTexture(t, subresources, clearDepth, depth, clearStencil, stencil);
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

void c_nvrhi_commandList_beginTrackingBufferState(
		nvrhi::ICommandList* commandList,
		nvrhi::IBuffer* buffer,
		nvrhi::ResourceStates stateBits)
{
	commandList->beginTrackingBufferState(buffer, stateBits);
}

void c_nvrhi_commandList_writeBuffer(
		nvrhi::ICommandList* commandList,
		nvrhi::IBuffer* b,
		const void* data,
		size_t dataSize,
		uint64_t destOffsetBytes)
{
	commandList->writeBuffer(b, data, dataSize, destOffsetBytes);
}

void c_nvrhi_commandList_setPermanentBufferState(
		nvrhi::ICommandList* commandList,
		nvrhi::IBuffer* buffer,
		nvrhi::ResourceStates stateBits)
{
	commandList->setPermanentBufferState(buffer, stateBits);
}

void c_nvrhi_commandList_draw(nvrhi::ICommandList* commandList, const nvrhi::DrawArguments* args)
{
	commandList->draw(*args);
}

void c_nvrhi_commandList_drawIndexed(nvrhi::ICommandList* commandList, const nvrhi::DrawArguments* args)
{
	commandList->drawIndexed(*args);
}

void c_nvrhi_commandList_setPushConstants(
		nvrhi::ICommandList* commandList,
		const void* data,
		size_t byteSize)
{
	commandList->setPushConstants(data, byteSize);
}

void c_nvrhi_commandList_setGraphicsState(
		nvrhi::ICommandList* commandList,
		const nvrhi::GraphicsState* state)
{
	commandList->setGraphicsState(*state);
}

unsigned long c_nvrhi_resource_addRef(nvrhi::IResource* res) {
	return res->AddRef();
}

unsigned long c_nvrhi_resource_release(nvrhi::IResource* res) {
	return res->Release();
}

void c_cpp_string_set(void* string_ptr, const char* value)
{
	auto string = reinterpret_cast<std::string*>(string_ptr);
	*string = std::string(value);
}

const char* c_cpp_string_get(const void* string_ptr)
{
	auto string = reinterpret_cast<const std::string*>(string_ptr);

	return string->c_str();
}

const nvrhi::FramebufferInfoEx* c_nvrhi_framebuffer_getFramebufferInfo(const nvrhi::IFramebuffer* framebuffer)
{
	return &framebuffer->getFramebufferInfo();
}

const nvrhi::FramebufferDesc* c_nvrhi_framebuffer_getDesc(
		const nvrhi::IFramebuffer* framebuffer)
{
	return &framebuffer->getDesc();
}

const nvrhi::BufferDesc* c_nvrhi_buffer_getDesc(const nvrhi::IBuffer* buffer)
{
	return &buffer->getDesc();
}

const nvrhi::FormatInfo* c_nvrhi_getFormatInfo(nvrhi::Format format) {
	return &nvrhi::getFormatInfo(format);
}

const nvrhi::TextureDesc* c_nvrhi_texture_getDesc(const nvrhi::ITexture* texture)
{
	return &texture->getDesc();
}

const nvrhi::BindingSetDesc* c_nvrhi_bindingSet_getDesc(const nvrhi::IBindingSet* set)
{
	return set->getDesc();
}

bool c_nvrhi_bindingSetDesc_eql(
		const nvrhi::BindingSetDesc* a,
		const nvrhi::BindingSetDesc* b)
{
	return *a == *b;
}

void c_nvrhi_bindingSetDesc_hashCombine(const nvrhi::BindingSetDesc* desc, size_t* seed)
{
	nvrhi::hash_combine(*seed, *desc);
}


const nvrhi::SamplerDesc* c_nvrhi_sampler_getDesc(const nvrhi::ISampler* sampler)
{
	return &sampler->getDesc();
}

void c_nvrhi_samplerDesc_hashCombine(const nvrhi::SamplerDesc* desc, size_t* seed)
{
	nvrhi::hash_combine(*seed, *desc);
}

void c_nvrhi_hashCombine_ptr(size_t* seed, void* ptr)
{
	nvrhi::hash_combine(*seed, ptr);
}

void c_nvrhi_hashCombine_u64(size_t* seed, uint64_t u)
{
	nvrhi::hash_combine(*seed, u);
}

void c_nvrhi_hashCombine_float(size_t* seed, float f)
{
	nvrhi::hash_combine(*seed, f);
}

void c_nvrhi_hashCombine_int(size_t* seed, int i) {
	nvrhi::hash_combine(*seed, i);
}

// vulkan

VkFormat c_nvrhi_vulkan_convertFormat(nvrhi::Format format) {
	return nvrhi::vulkan::convertFormat(format);
}

void c_nvrhi_vulkan_createDevice(
		const nvrhi::vulkan::DeviceDesc* desc,
		nvrhi::DeviceHandle* handle,
		PFN_vkGetInstanceProcAddr vkGetInstanceProcAddr)
{
	VULKAN_HPP_DEFAULT_DISPATCHER.init(desc->instance, vkGetInstanceProcAddr, desc->device);
	*handle = nvrhi::vulkan::createDevice(*desc);
}

void c_nvrhi_vulkan_device_queueSignalSemaphore(
		nvrhi::vulkan::IDevice* device,
		nvrhi::CommandQueue executionQueue,
		VkSemaphore semaphore,
		uint64_t value)
{
	device->queueSignalSemaphore(executionQueue, semaphore, value);
}

void c_nvrhi_vulkan_device_queueWaitForSemaphore(
		nvrhi::vulkan::IDevice* device,
		nvrhi::CommandQueue waitQueue,
		VkSemaphore semaphore,
		uint64_t value)
{
	device->queueWaitForSemaphore(waitQueue, semaphore, value);
}

// utils

nvrhi::BufferDesc c_nvrhi_utils_createVolatileConstantBufferDesc(
		uint32_t byteSize,
		const char* debugName,
		uint32_t maxVersions)
{
	return nvrhi::utils::CreateVolatileConstantBufferDesc(byteSize, debugName, maxVersions);
}

void c_nvrhi_utils_clearColorAttachment(
		nvrhi::ICommandList* commandList,
		nvrhi::IFramebuffer* framebuffer,
		uint32_t attachmentIndex,
		nvrhi::Color color)
{
	nvrhi::utils::ClearColorAttachment(commandList, framebuffer, attachmentIndex, color);
}
