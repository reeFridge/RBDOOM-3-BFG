/*
===========================================================================

Doom 3 BFG Edition GPL Source Code
Copyright (C) 1993-2012 id Software LLC, a ZeniMax Media company.
Copyright (C) 2013-2022 Robert Beckebans
Copyright (C) 2016-2017 Dustin Land
Copyright (C) 2022 Stephen Pridham

This file is part of the Doom 3 BFG Edition GPL Source Code ("Doom 3 BFG Edition Source Code").

Doom 3 BFG Edition Source Code is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Doom 3 BFG Edition Source Code is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Doom 3 BFG Edition Source Code.  If not, see <http://www.gnu.org/licenses/>.

In addition, the Doom 3 BFG Edition Source Code is also subject to certain additional terms. You should have received a copy of these additional terms immediately following the terms and conditions of the GNU General Public License which accompanied the Doom 3 BFG Edition Source Code.  If not, please request a copy in writing from id Software at the address below.

If you have questions concerning this license or the applicable additional terms, you may contact in writing id Software LLC, c/o ZeniMax Media Inc., Suite 120, Rockville, Maryland 20850 USA.

===========================================================================
*/

#include "precompiled.h"
#pragma hdrstop

#include "../RenderCommon.h"
#include "../RenderBackend.h"
#include "../../framework/Common_local.h"
#include "imgui.h"
#include "../ImmediateMode.h"

#include "nvrhi/utils.h"
#include <sys/DeviceManager.h>
extern DeviceManager* deviceManager;
extern idCVar r_graphicsAPI;

idCVar r_drawFlickerBox( "r_drawFlickerBox", "0", CVAR_RENDERER | CVAR_BOOL, "visual test for dropping frames" );
idCVar stereoRender_warp( "stereoRender_warp", "0", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_BOOL, "use the optical warping renderprog instead of stereoDeGhost" );
idCVar stereoRender_warpStrength( "stereoRender_warpStrength", "1.45", CVAR_RENDERER | CVAR_ARCHIVE | CVAR_FLOAT, "amount of pre-distortion" );

idCVar stereoRender_warpCenterX( "stereoRender_warpCenterX", "0.5", CVAR_RENDERER | CVAR_FLOAT | CVAR_ARCHIVE, "center for left eye, right eye will be 1.0 - this" );
idCVar stereoRender_warpCenterY( "stereoRender_warpCenterY", "0.5", CVAR_RENDERER | CVAR_FLOAT | CVAR_ARCHIVE, "center for both eyes" );
idCVar stereoRender_warpParmZ( "stereoRender_warpParmZ", "0", CVAR_RENDERER | CVAR_FLOAT | CVAR_ARCHIVE, "development parm" );
idCVar stereoRender_warpParmW( "stereoRender_warpParmW", "0", CVAR_RENDERER | CVAR_FLOAT | CVAR_ARCHIVE, "development parm" );
idCVar stereoRender_warpTargetFraction( "stereoRender_warpTargetFraction", "1.0", CVAR_RENDERER | CVAR_FLOAT | CVAR_ARCHIVE, "fraction of half-width the through-lens view covers" );

idCVar r_showSwapBuffers( "r_showSwapBuffers", "0", CVAR_BOOL, "Show timings from GL_BlockingSwapBuffers" );
idCVar r_syncEveryFrame( "r_syncEveryFrame", "1", CVAR_BOOL, "Don't let the GPU buffer execution past swapbuffers" );

idCVar r_vkUploadBufferSizeMB( "r_vkUploadBufferSizeMB", "64", CVAR_INTEGER | CVAR_INIT | CVAR_NEW, "Size of gpu upload buffer (Vulkan only)" );


constexpr std::size_t MAX_IMAGE_PARMS = 16;

class NvrhiContext
{
public:
	int										currentImageParm = 0;
	idArray< idImage*, MAX_IMAGE_PARMS >	imageParms;
	idScreenRect							scissor;		// set by GL_Scissor

	void	operator=( NvrhiContext& other );
	bool	operator==( NvrhiContext& other ) const;
	bool	operator!=( NvrhiContext& other ) const;
};

/*
==================
NvrhiContext::operator=
==================
*/
void NvrhiContext::operator=( NvrhiContext& other )
{
	currentImageParm = other.currentImageParm;
	for( int i = 0; i < imageParms.Num(); i++ )
	{
		imageParms[i] = other.imageParms[i];
	}

	scissor = other.scissor;
}

/*
==================
NvrhiContext::operator==
==================
*/
bool NvrhiContext::operator==( NvrhiContext& other ) const
{
	if( this == &other )
	{
		return true;
	}

	if( currentImageParm != other.currentImageParm )
	{
		return false;
	}

	for( int i = 0; i < imageParms.Num(); i++ )
	{
		if( imageParms[i] != other.imageParms[i] )
		{
			return false;
		}
	}

	if( scissor != other.scissor )
	{
		return false;
	}

	return true;
}

/*
==================
NvrhiContext::operator!=
==================
*/
bool NvrhiContext::operator!=( NvrhiContext& other ) const
{
	return !( *this == other );
}

static NvrhiContext context;
static NvrhiContext prevContext;


/*
==================
R_InitOpenGL

This function is responsible for initializing a valid OpenGL subsystem
for rendering.  This is done by calling the system specific GLimp_Init,
which gives us a working OGL subsystem, then setting all necessary openGL
state, including images, vertex programs, and display lists.

Changes to the vertex cache size or smp state require a vid_restart.

If R_IsInitialized() is false, no rendering can take place, but
all renderSystem functions will still operate properly, notably the material
and model information functions.
==================
*/
void idRenderBackend::Init()
{
	common->Printf( "----- R_InitOpenGL -----\n" );

	if( tr.IsInitialized() )
	{
		common->FatalError( "R_InitOpenGL called while active" );
	}

	// SRS - create deviceManager here to prevent allocation loop via R_SetNewMode( true )
	nvrhi::GraphicsAPI api = nvrhi::GraphicsAPI::D3D12;
	if( !idStr::Icmp( r_graphicsAPI.GetString(), "vulkan" ) )
	{
		api = nvrhi::GraphicsAPI::VULKAN;
	}
	else if( !idStr::Icmp( r_graphicsAPI.GetString(), "dx12" ) )
	{
		api = nvrhi::GraphicsAPI::D3D12;
	}
	deviceManager = DeviceManager::Create( api );

	// DG: make sure SDL has setup video so getting supported modes in R_SetNewMode() works
#if defined( VULKAN_USE_PLATFORM_SDL )
	VKimp_PreInit();
#else
	GLimp_PreInit();
#endif
	// DG end

	R_SetNewMode( true );

	// input and sound systems need to be tied to the new window
	Sys_InitInput();

	// clear NVRHI context
	context.currentImageParm = 0;
	context.imageParms.Zero();

	// Need to reinitialize this pass once this image is resized.
	renderProgManager.Init( deviceManager->GetDevice() );
	renderLog.Init();

	bindingCache.Init( deviceManager->GetDevice() );
	samplerCache.Init( deviceManager->GetDevice() );
	pipelineCache.Init( deviceManager->GetDevice() );
	commonPasses.Init( deviceManager->GetDevice() );
	hiZGenPass = nullptr;
	ssaoPass = nullptr;

	// Maximum resolution of one tile within tiled shadow map. Resolution must be power of two and
	// square, since quad-tree for managing tiles will not work correctly otherwise. Furthermore
	// resolution must be at least 16.
	const int MAX_TILE_RES = shadowMapResolutions[ 0 ];

	// Specifies how many levels the quad-tree for managing tiles within tiled shadow map should
	// have. The higher the value, the smaller the resolution of the smallest used tile will be.
	// In the current configuration of 8192 resolution and 8 levels, the smallest tile will have
	// a resolution of 64. 16 is the smallest allowed value for the min tile resolution.
	const int NUM_QUAD_TREE_LEVELS = 8;

	tileMap.Init( r_shadowMapAtlasSize.GetInteger(), MAX_TILE_RES, NUM_QUAD_TREE_LEVELS );

	tr.SetInitialized();

	if( !commandList )
	{
		nvrhi::CommandListParameters params = {};
		if( deviceManager->GetGraphicsAPI() == nvrhi::GraphicsAPI::VULKAN )
		{
			// SRS - set upload buffer size to avoid Vulkan staging buffer fragmentation
			size_t maxBufferSize = ( size_t )( r_vkUploadBufferSizeMB.GetInteger() * 1024 * 1024 );
			params.setUploadChunkSize( maxBufferSize );
		}
		commandList = deviceManager->GetDevice()->createCommandList( params );
	}

	// allocate the vertex array range or vertex objects
	commandList->open();
	vertexCache.Init( glConfig.uniformBufferOffsetAlignment, commandList );
	commandList->close();
	deviceManager->GetDevice()->executeCommandList( commandList );

	fhImmediateMode::Init( commandList );

	// allocate the frame data, which may be more if smp is enabled
	if (USE_ZTECH_FRAME_DATA)
		ztech_frameData_init();
	else
		R_InitFrameData();

	// TODO REMOVE: reset our gamma
	R_SetColorMappings();

	slopeScaleBias = 0.f;
	depthBias = 0.f;

	currentBindingSets.SetNum( currentBindingSets.Max() );
	pendingBindingSetDescs.SetNum( pendingBindingSetDescs.Max() );

	prevMVP[0] = renderMatrix_identity;
	prevMVP[1] = renderMatrix_identity;
	prevViewsValid = false;

	currentVertexBuffer = nullptr;
	currentIndexBuffer = nullptr;
	currentJointBuffer = nullptr;
	currentVertexOffset = 0;
	currentIndexOffset = 0;
	currentJointOffset = 0;
	prevBindingLayoutType = -1;

	deviceManager->GetDevice()->waitForIdle();
	deviceManager->GetDevice()->runGarbageCollection();
}

void idRenderBackend::Shutdown()
{
	// SRS - Clean up NVRHI resources before Sys_Quit(), otherwise non-zero exit code (destructors too late)

	// Clear all cached pipeline data
	tr.backend.ClearCaches();
	pipelineCache.Shutdown();

	// Delete all renderpass resources
	commonPasses.Shutdown();

	// Delete current binding sets
	for( int i = 0; i < currentBindingSets.Num(); i++ )
	{
		currentBindingSets[i].Reset();
	}

	// Unload shaders, delete binding layouts, and unmap memory
	renderProgManager.Shutdown();

	// Delete renderlog command buffer and timer query resources
	renderLog.Shutdown();

	// Delete command list
	commandList.Reset();

	// Delete immediate mode buffer objects
	fhImmediateMode::Shutdown();

#if defined( VULKAN_USE_PLATFORM_SDL )
	VKimp_Shutdown( true );		// SRS - shutdown SDL on quit
#else
	GLimp_Shutdown();
#endif

	// SRS - delete deviceManager instance on backend shutdown
	if( deviceManager )
	{
		delete deviceManager;
		deviceManager = NULL;
	}
}

/*
=============
idRenderBackend::DrawElementsWithCounters
=============
*/
void idRenderBackend::DrawElementsWithCounters( const drawSurf_t* surf, bool shadowCounter )
{
	//
	// get vertex buffer
	//
	const vertCacheHandle_t vbHandle = surf->ambientCache;
	idVertexBuffer* vertexBuffer;
	if( vertexCache.CacheIsStatic( vbHandle ) )
	{
		vertexBuffer = &vertexCache.staticData.vertexBuffer;
	}
	else
	{
		const uint64 frameNum = static_cast<uint64>( vbHandle >> VERTCACHE_FRAME_SHIFT ) & VERTCACHE_FRAME_MASK;
		if( frameNum != ( ( vertexCache.currentFrame - 1 ) & VERTCACHE_FRAME_MASK ) )
		{
			idLib::Warning( "RB_DrawElementsWithCounters, vertexBuffer == NULL" );
			return;
		}
		vertexBuffer = &vertexCache.frameData[vertexCache.drawListNum].vertexBuffer;
	}
	const uint vertOffset = static_cast<uint>( vbHandle >> VERTCACHE_OFFSET_SHIFT ) & VERTCACHE_OFFSET_MASK;

	bool changeState = false;

	if( currentVertexOffset != vertOffset )
	{
		currentVertexOffset = vertOffset;
	}

	if( currentVertexBuffer != vertexBuffer->GetAPIObject() || !r_useStateCaching.GetBool() )
	{
		currentVertexBuffer = vertexBuffer->GetAPIObject();
		changeState = true;
	}

	//
	// get index buffer
	//
	const vertCacheHandle_t ibHandle = surf->indexCache;
	idIndexBuffer* indexBuffer;
	if( vertexCache.CacheIsStatic( ibHandle ) )
	{
		indexBuffer = &vertexCache.staticData.indexBuffer;
	}
	else
	{
		const uint64 frameNum = static_cast<uint64>( ibHandle >> VERTCACHE_FRAME_SHIFT ) & VERTCACHE_FRAME_MASK;
		if( frameNum != ( ( vertexCache.currentFrame - 1 ) & VERTCACHE_FRAME_MASK ) )
		{
			idLib::Warning( "RB_DrawElementsWithCounters, indexBuffer == NULL" );
			return;
		}
		indexBuffer = &vertexCache.frameData[vertexCache.drawListNum].indexBuffer;
	}
	const uint indexOffset = static_cast<uint>( ibHandle >> VERTCACHE_OFFSET_SHIFT ) & VERTCACHE_OFFSET_MASK;

	if( currentIndexOffset != indexOffset )
	{
		currentIndexOffset = indexOffset;
	}

	if( currentIndexBuffer != indexBuffer->GetAPIObject() || !r_useStateCaching.GetBool() )
	{
		currentIndexBuffer = indexBuffer->GetAPIObject();
		changeState = true;
	}

	//
	// get GPU Skinning joint buffer
	//
	const vertCacheHandle_t jointHandle = surf->jointCache;
	currentJointBuffer = nullptr;
	currentJointOffset = 0;

#if 0
	if( jointHandle )
	{
		//if( !verify( renderProgManager.ShaderUsesJoints() ) )
		if( !renderProgManager.ShaderUsesJoints() )
		{
			return;
		}
	}
	else
	{
		if( !verify( !renderProgManager.ShaderUsesJoints() || renderProgManager.ShaderHasOptionalSkinning() ) )
		{
			return;
		}
	}
#endif

	if( jointHandle )
	{
		const idUniformBuffer* jointBuffer = nullptr;

		if( vertexCache.CacheIsStatic( jointHandle ) )
		{
			jointBuffer = &vertexCache.staticData.jointBuffer;
		}
		else
		{
			const uint64 frameNum = static_cast<uint64>( jointHandle >> VERTCACHE_FRAME_SHIFT ) & VERTCACHE_FRAME_MASK;
			if( frameNum != ( ( vertexCache.currentFrame - 1 ) & VERTCACHE_FRAME_MASK ) )
			{
				idLib::Warning( "RB_DrawElementsWithCounters, jointBuffer == NULL" );
				return;
			}
			jointBuffer = &vertexCache.frameData[vertexCache.drawListNum].jointBuffer;
		}

		uint offset = static_cast<uint>( jointHandle >> VERTCACHE_OFFSET_SHIFT ) & VERTCACHE_OFFSET_MASK;
		if( currentJointBuffer != jointBuffer->GetAPIObject() || currentJointOffset != offset )
		{
			changeState = true;
		}

		currentJointBuffer = jointBuffer->GetAPIObject();
		currentJointOffset = offset;
	}

	//
	// set up matching binding layout
	//
	const int bindingLayoutType = renderProgManager.BindingLayoutType();

	idStaticList<nvrhi::BindingLayoutHandle, nvrhi::c_MaxBindingLayouts>* layouts
		= renderProgManager.GetBindingLayout( bindingLayoutType );

	if( changeState || bindingLayoutType != prevBindingLayoutType || context != prevContext )
	{
		GetCurrentBindingLayout( bindingLayoutType );

		for( int i = 0; i < layouts->Num(); i++ )
		{
			if( !currentBindingSets[i] || *currentBindingSets[i]->getDesc() != pendingBindingSetDescs[bindingLayoutType][i] )
			{
				currentBindingSets[i] = bindingCache.GetOrCreateBindingSet( pendingBindingSetDescs[bindingLayoutType][i], ( *layouts )[i] );
				changeState = true;
			}
		}
	}

	const int program = renderProgManager.CurrentProgram();
	const PipelineKey key{ glStateBits, program, static_cast<int>( depthBias ), slopeScaleBias, currentFrameBuffer };
	const auto pipeline = pipelineCache.GetOrCreatePipeline( key );

	if( currentPipeline != pipeline )
	{
		currentPipeline = pipeline;
		changeState = true;
	}

	if( !currentViewport.Equals( stateViewport ) )
	{
		stateViewport = currentViewport;
		changeState = true;
	}

	if( !context.scissor.Equals( stateScissor ) )
	{
		changeState = true;
		stateScissor = context.scissor;
	}

	if( renderProgManager.CommitConstantBuffer( commandList, bindingLayoutType != prevBindingLayoutType ) )
	{
		if( deviceManager->GetGraphicsAPI() == nvrhi::GraphicsAPI::VULKAN )
		{
			// Reset the graphics state if the constant buffer is written to since
			// the render pass is ended for vulkan. setGraphicsState will
			// reinstate the render pass.
			changeState = true;
		}
	}

	//
	// create new graphics state if necessary
	//
	if( changeState )
	{
		nvrhi::GraphicsState state;

		for( int i = 0; i < layouts->Num(); i++ )
		{
			state.bindings.push_back( currentBindingSets[i] );
		}

		state.indexBuffer = { currentIndexBuffer, nvrhi::Format::R16_UINT, 0 };
		state.vertexBuffers = { { currentVertexBuffer, 0, 0 } };
		state.pipeline = pipeline;
		state.framebuffer = currentFrameBuffer->GetApiObject();

		nvrhi::Viewport viewport{ ( float )currentViewport.x1,
								  ( float )currentViewport.x2,
								  ( float )currentViewport.y1,
								  ( float )currentViewport.y2,
								  0.0f,
								  1.0f };
		state.viewport.addViewport( viewport );

		if( !context.scissor.IsEmpty() )
		{
			state.viewport.addScissorRect( nvrhi::Rect( context.scissor.x1, context.scissor.x2, context.scissor.y1, context.scissor.y2 ) );
		}
		else
		{
			state.viewport.addScissorRect( nvrhi::Rect( viewport ) );
		}

		commandList->setGraphicsState( state );
	}

	//
	// draw command
	//
	nvrhi::DrawArguments args;
	args.startVertexLocation = currentVertexOffset / sizeof( idDrawVert );
	args.startIndexLocation = currentIndexOffset / sizeof( triIndex_t );
	args.vertexCount = surf->numIndexes;
	commandList->drawIndexed( args );

	// keep track of last context to avoid setting up the binding layout and binding set again.
	prevContext = context;
	prevBindingLayoutType = bindingLayoutType;

	if( shadowCounter )
	{
		pc.c_shadowElements++;
		pc.c_shadowIndexes += surf->numIndexes;
	}
	else
	{
		pc.c_drawElements++;
		pc.c_drawIndexes += surf->numIndexes;
	}
}

void idRenderBackend::GetCurrentBindingLayout( int type )
{
	constexpr auto numBoneMatrices = 480;
	auto& desc = pendingBindingSetDescs[type];

	if( desc.Num() == 0 )
	{
		desc.SetNum( nvrhi::c_MaxBindingLayouts );
	}

	nvrhi::IBuffer* paramCb = renderProgManager.ConstantBuffer();
	auto range = nvrhi::EntireBuffer;

	if( type == BINDING_LAYOUT_DEFAULT )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() )
			};
		}
		else
		{
			desc[1].bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
		}

		if( desc[2].bindings.empty() )
		{
			desc[2].bindings =
			{
				nvrhi::BindingSetItem::Sampler( 0, ( nvrhi::ISampler* )GetImageAt( 0 )->GetSampler( samplerCache ) )
			};
		}
		else
		{
			desc[2].bindings[0].resourceHandle = ( nvrhi::ISampler* )GetImageAt( 0 )->GetSampler( samplerCache );
		}
	}
	else if( type == BINDING_LAYOUT_DEFAULT_SKINNED )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::StructuredBuffer_SRV( 11, currentJointBuffer, nvrhi::Format::UNKNOWN, nvrhi::BufferRange( currentJointOffset, sizeof( idVec4 ) * numBoneMatrices ) )
			};
		}
		else
		{
			auto& bindings = desc[0].bindings;
			bindings[0].resourceHandle = paramCb;
			bindings[0].range = range;
			bindings[1].resourceHandle = currentJointBuffer;
			bindings[1].range = nvrhi::BufferRange{ currentJointOffset, sizeof( idVec4 )* numBoneMatrices };
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() )
			};
		}
		else
		{
			desc[1].bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
		}

		if( desc[2].bindings.empty() )
		{
			desc[2].bindings =
			{
				nvrhi::BindingSetItem::Sampler( 0, ( nvrhi::ISampler* )GetImageAt( 0 )->GetSampler( samplerCache ) )
			};
		}
		else
		{
			desc[2].bindings[0].resourceHandle = ( nvrhi::ISampler* )GetImageAt( 0 )->GetSampler( samplerCache );
		}
	}
	else if( type == BINDING_LAYOUT_CONSTANT_BUFFER_ONLY )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
		}
	}
	else if( type == BINDING_LAYOUT_CONSTANT_BUFFER_ONLY_SKINNED )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::StructuredBuffer_SRV( 11, currentJointBuffer, nvrhi::Format::UNKNOWN, nvrhi::BufferRange( currentJointOffset, sizeof( idVec4 ) * numBoneMatrices ) )
			};
		}
		else
		{
			auto& bindings = desc[0].bindings;
			bindings[0].resourceHandle = paramCb;
			bindings[0].range = range;
			bindings[1].resourceHandle = currentJointBuffer;
			bindings[1].range = nvrhi::BufferRange{ currentJointOffset, sizeof( idVec4 )* numBoneMatrices };
		}
	}
	else if( type == BINDING_LAYOUT_AMBIENT_LIGHTING_IBL )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 2, ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID() )
			};
		}
		else
		{
			desc[1].bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			desc[1].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
			desc[1].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID();
		}

		if( desc[2].bindings.empty() )
		{
			desc[2].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 3, ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 4, ( nvrhi::ITexture* )GetImageAt( 4 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 7, ( nvrhi::ITexture* )GetImageAt( 7 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 8, ( nvrhi::ITexture* )GetImageAt( 8 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 9, ( nvrhi::ITexture* )GetImageAt( 9 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 10, ( nvrhi::ITexture* )GetImageAt( 10 )->GetTextureID() )
			};
		}
		else
		{
			desc[2].bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID();
			desc[2].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 4 )->GetTextureID();
			desc[2].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 7 )->GetTextureID();
			desc[2].bindings[3].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 8 )->GetTextureID();
			desc[2].bindings[4].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 9 )->GetTextureID();
			desc[2].bindings[5].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 10 )->GetTextureID();
		}

		if( R_UsePixelatedLook() )
		{
			if( desc[3].bindings.empty() )
			{
				desc[3].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointWrapSampler ),
					nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearClampSampler )
				};
			}
			else
			{
				desc[3].bindings[0].resourceHandle = commonPasses.m_PointWrapSampler;
				desc[3].bindings[1].resourceHandle = commonPasses.m_LinearClampSampler;
			}
		}
		else
		{
			if( desc[3].bindings.empty() )
			{
				desc[3].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_AnisotropicWrapSampler ),
					nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearClampSampler )
				};
			}
			else
			{
				desc[3].bindings[0].resourceHandle = commonPasses.m_AnisotropicWrapSampler;
				desc[3].bindings[1].resourceHandle = commonPasses.m_LinearClampSampler;
			}
		}
	}
	else if( type == BINDING_LAYOUT_AMBIENT_LIGHTING_IBL_SKINNED )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::StructuredBuffer_SRV( 11, currentJointBuffer, nvrhi::Format::UNKNOWN, nvrhi::BufferRange( currentJointOffset, sizeof( idVec4 ) * numBoneMatrices ) )
			};
		}
		else
		{
			auto& bindings = desc[0].bindings;
			bindings[0].resourceHandle = paramCb;
			bindings[0].range = range;
			bindings[1].resourceHandle = currentJointBuffer;
			bindings[1].range = nvrhi::BufferRange{ currentJointOffset, sizeof( idVec4 )* numBoneMatrices };
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 2, ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID() )
			};
		}
		else
		{
			desc[1].bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			desc[1].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
			desc[1].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID();
		}

		if( desc[2].bindings.empty() )
		{
			desc[2].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 3, ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 4, ( nvrhi::ITexture* )GetImageAt( 4 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 7, ( nvrhi::ITexture* )GetImageAt( 7 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 8, ( nvrhi::ITexture* )GetImageAt( 8 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 9, ( nvrhi::ITexture* )GetImageAt( 9 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 10, ( nvrhi::ITexture* )GetImageAt( 10 )->GetTextureID() )
			};
		}
		else
		{
			desc[2].bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID();
			desc[2].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 4 )->GetTextureID();
			desc[2].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 7 )->GetTextureID();
			desc[2].bindings[3].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 8 )->GetTextureID();
			desc[2].bindings[4].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 9 )->GetTextureID();
			desc[2].bindings[5].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 10 )->GetTextureID();
		}

		if( R_UsePixelatedLook() )
		{
			if( desc[3].bindings.empty() )
			{
				desc[3].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointWrapSampler ),
					nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearClampSampler )
				};
			}
			else
			{
				desc[3].bindings[0].resourceHandle = commonPasses.m_PointWrapSampler;
				desc[3].bindings[1].resourceHandle = commonPasses.m_LinearClampSampler;
			}
		}
		else
		{
			if( desc[3].bindings.empty() )
			{
				desc[3].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_AnisotropicWrapSampler ),
					nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearClampSampler )
				};
			}
			else
			{
				desc[3].bindings[0].resourceHandle = commonPasses.m_AnisotropicWrapSampler;
				desc[3].bindings[1].resourceHandle = commonPasses.m_LinearClampSampler;
			}
		}
	}
	else if( type == BINDING_LAYOUT_DRAW_AO )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 2, ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID() )
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
			desc[0].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			desc[0].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
			desc[0].bindings[3].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID();
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointWrapSampler )  // blue noise
			};
		}
		else
		{
			desc[1].bindings[0] = nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointWrapSampler );
		}
	}
	else if( type == BINDING_LAYOUT_DRAW_INTERACTION )
	{
		// renderparms: 0
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
		}

		// materials: 1
		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 2, ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID() )
			};
		}
		else
		{
			desc[1].bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			desc[1].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
			desc[1].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID();
		}

		// light projection: 2
		if( desc[2].bindings.empty() )
		{
			desc[2].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 3, ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 4, ( nvrhi::ITexture* )GetImageAt( 4 )->GetTextureID() )
			};
		}
		else
		{
			desc[2].bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID();
			desc[2].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 4 )->GetTextureID();
		}

		// samplers: 3
		if( R_UsePixelatedLook() )
		{
			if( desc[3].bindings.empty() )
			{
				desc[3].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointWrapSampler ),
					nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearBorderSampler )
				};
			}
			else
			{
				desc[3].bindings[0].resourceHandle = commonPasses.m_PointWrapSampler;
				desc[3].bindings[1].resourceHandle = commonPasses.m_LinearBorderSampler;
			}
		}
		else
		{
			if( desc[3].bindings.empty() )
			{
				desc[3].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_AnisotropicWrapSampler ),
					nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearBorderSampler )
				};
			}
			else
			{
				desc[3].bindings[0].resourceHandle = commonPasses.m_AnisotropicWrapSampler;
				desc[3].bindings[1].resourceHandle = commonPasses.m_LinearBorderSampler;
			}
		}
	}
	else if( type == BINDING_LAYOUT_DRAW_INTERACTION_SKINNED )
	{
		// renderparms / skinning joints: 0
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::StructuredBuffer_SRV( 11, currentJointBuffer, nvrhi::Format::UNKNOWN, nvrhi::BufferRange( currentJointOffset, sizeof( idVec4 ) * numBoneMatrices ) )
			};
		}
		else
		{
			auto& bindings = desc[0].bindings;
			bindings[0].resourceHandle = paramCb;
			bindings[0].range = range;
			bindings[1].resourceHandle = currentJointBuffer;
			bindings[1].range = nvrhi::BufferRange{ currentJointOffset, sizeof( idVec4 )* numBoneMatrices };
		}

		// materials: 1
		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 2, ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID() )
			};
		}
		else
		{
			desc[1].bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			desc[1].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
			desc[1].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID();
		}

		// light projection: 2
		if( desc[2].bindings.empty() )
		{
			desc[2].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 3, ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 4, ( nvrhi::ITexture* )GetImageAt( 4 )->GetTextureID() )
			};
		}
		else
		{
			desc[2].bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID();
			desc[2].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 4 )->GetTextureID();
		}

		// samplers: 3
		if( R_UsePixelatedLook() )
		{
			if( desc[3].bindings.empty() )
			{
				desc[3].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointWrapSampler ),
					nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearBorderSampler )
				};
			}
			else
			{
				desc[3].bindings[0].resourceHandle = commonPasses.m_PointWrapSampler;
				desc[3].bindings[1].resourceHandle = commonPasses.m_LinearBorderSampler;
			}
		}
		else
		{
			if( desc[3].bindings.empty() )
			{
				desc[3].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_AnisotropicWrapSampler ),
					nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearBorderSampler )
				};
			}
			else
			{
				desc[3].bindings[0].resourceHandle = commonPasses.m_AnisotropicWrapSampler;
				desc[3].bindings[1].resourceHandle = commonPasses.m_LinearBorderSampler;
			}
		}
	}
	else if( type == BINDING_LAYOUT_DRAW_INTERACTION_SM )
	{
		// renderparms: 0
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
		}

		// materials: 1
		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 2, ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID() )
			};
		}
		else
		{
			auto& bindings = desc[1].bindings;
			bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
			bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID();
		}

		// light projection: 2
		if( desc[2].bindings.empty() )
		{
			auto& bindings = desc[2].bindings;
			bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 3, ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 4, ( nvrhi::ITexture* )GetImageAt( 4 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 5, ( nvrhi::ITexture* )GetImageAt( 5 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 6, ( nvrhi::ITexture* )GetImageAt( 6 )->GetTextureID() )
			};
		}
		else
		{
			auto& bindings = desc[2].bindings;
			bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID();
			bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 4 )->GetTextureID();
			bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 5 )->GetTextureID();
			bindings[3].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 6 )->GetTextureID();
		}

		// samplers: 3
		if( R_UsePixelatedLook() )
		{
			if( desc[3].bindings.empty() )
			{
				auto& bindings = desc[3].bindings;
				bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointWrapSampler ),
					nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearBorderSampler ),
					nvrhi::BindingSetItem::Sampler( 2, commonPasses.m_LinearClampCompareSampler ),
					nvrhi::BindingSetItem::Sampler( 3, commonPasses.m_PointWrapSampler )  // blue noise
				};
			}
			else
			{
				auto& bindings = desc[3].bindings;
				bindings[0].resourceHandle = commonPasses.m_PointWrapSampler;
				bindings[1].resourceHandle = commonPasses.m_LinearBorderSampler;
				bindings[2].resourceHandle = commonPasses.m_LinearClampCompareSampler;
				bindings[3].resourceHandle = commonPasses.m_PointWrapSampler;
			}
		}
		else
		{
			if( desc[3].bindings.empty() )
			{
				auto& bindings = desc[3].bindings;
				bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_AnisotropicWrapSampler ),
					nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearBorderSampler ),
					nvrhi::BindingSetItem::Sampler( 2, commonPasses.m_LinearClampCompareSampler ),
					nvrhi::BindingSetItem::Sampler( 3, commonPasses.m_PointWrapSampler )  // blue noise
				};
			}
			else
			{
				auto& bindings = desc[3].bindings;
				bindings[0].resourceHandle = commonPasses.m_AnisotropicWrapSampler;
				bindings[1].resourceHandle = commonPasses.m_LinearBorderSampler;
				bindings[2].resourceHandle = commonPasses.m_LinearClampCompareSampler;
				bindings[3].resourceHandle = commonPasses.m_PointWrapSampler;
			}
		}
	}
	else if( type == BINDING_LAYOUT_DRAW_INTERACTION_SM_SKINNED )
	{
		// renderparms: 0
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::StructuredBuffer_SRV( 11, currentJointBuffer, nvrhi::Format::UNKNOWN, nvrhi::BufferRange( currentJointOffset, sizeof( idVec4 ) * numBoneMatrices ) )
			};
		}
		else
		{
			auto& bindings = desc[0].bindings;
			bindings[0].resourceHandle = paramCb;
			bindings[0].range = range;
			bindings[1].resourceHandle = currentJointBuffer;
			bindings[1].range = nvrhi::BufferRange{ currentJointOffset, sizeof( idVec4 )* numBoneMatrices };
		}

		// materials: 1
		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 2, ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID() )
			};
		}
		else
		{
			auto& bindings = desc[1].bindings;
			bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
			bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID();
		}

		// light projection: 2
		if( desc[2].bindings.empty() )
		{
			auto& bindings = desc[2].bindings;
			bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 3, ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 4, ( nvrhi::ITexture* )GetImageAt( 4 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 5, ( nvrhi::ITexture* )GetImageAt( 5 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 6, ( nvrhi::ITexture* )GetImageAt( 6 )->GetTextureID() )
			};
		}
		else
		{
			auto& bindings = desc[2].bindings;
			bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID();
			bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 4 )->GetTextureID();
			bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 5 )->GetTextureID();
			bindings[3].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 6 )->GetTextureID();
		}

		// samplers: 3
		if( R_UsePixelatedLook() )
		{
			if( desc[3].bindings.empty() )
			{
				auto& bindings = desc[3].bindings;
				bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointWrapSampler ),
					nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearBorderSampler ),
					nvrhi::BindingSetItem::Sampler( 2, commonPasses.m_LinearClampCompareSampler ),
					nvrhi::BindingSetItem::Sampler( 3, commonPasses.m_PointWrapSampler )  // blue noise
				};
			}
			else
			{
				auto& bindings = desc[3].bindings;
				bindings[0].resourceHandle = commonPasses.m_PointWrapSampler;
				bindings[1].resourceHandle = commonPasses.m_LinearBorderSampler;
				bindings[2].resourceHandle = commonPasses.m_LinearClampCompareSampler;
				bindings[3].resourceHandle = commonPasses.m_PointWrapSampler;
			}
		}
		else
		{
			if( desc[3].bindings.empty() )
			{
				auto& bindings = desc[3].bindings;
				bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_AnisotropicWrapSampler ),
					nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearBorderSampler ),
					nvrhi::BindingSetItem::Sampler( 2, commonPasses.m_LinearClampCompareSampler ),
					nvrhi::BindingSetItem::Sampler( 3, commonPasses.m_PointWrapSampler )  // blue noise
				};
			}
			else
			{
				auto& bindings = desc[3].bindings;
				bindings[0].resourceHandle = commonPasses.m_AnisotropicWrapSampler;
				bindings[1].resourceHandle = commonPasses.m_LinearBorderSampler;
				bindings[2].resourceHandle = commonPasses.m_LinearClampCompareSampler;
				bindings[3].resourceHandle = commonPasses.m_PointWrapSampler;
			}
		}
	}
	else if( type == BINDING_LAYOUT_FOG )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() )
			};
		}
		else
		{
			auto& bindings = desc[1].bindings;
			bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
		}

		if( desc[2].bindings.empty() )
		{
			desc[2].bindings =
			{
				nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_LinearClampSampler ),
				nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearClampSampler )
			};
		}
		else
		{
			auto& bindings = desc[2].bindings;
			bindings[0].resourceHandle = commonPasses.m_LinearClampSampler;
			bindings[1].resourceHandle = commonPasses.m_LinearClampSampler;
		}
	}
	else if( type == BINDING_LAYOUT_FOG_SKINNED )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::StructuredBuffer_SRV( 11, currentJointBuffer, nvrhi::Format::UNKNOWN, nvrhi::BufferRange( currentJointOffset, sizeof( idVec4 ) * numBoneMatrices ) )
			};
		}
		else
		{
			auto& bindings = desc[0].bindings;
			bindings[0].resourceHandle = paramCb;
			bindings[0].range = range;
			bindings[1].resourceHandle = currentJointBuffer;
			bindings[1].range = nvrhi::BufferRange{ currentJointOffset, sizeof( idVec4 )* numBoneMatrices };
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() )
			};
		}
		else
		{
			auto& bindings = desc[1].bindings;
			bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
		}

		if( desc[2].bindings.empty() )
		{
			desc[2].bindings =
			{
				nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_LinearClampSampler ),
				nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearClampSampler )
			};
		}
		else
		{
			auto& bindings = desc[2].bindings;
			bindings[0].resourceHandle = commonPasses.m_LinearClampSampler;
			bindings[1].resourceHandle = commonPasses.m_LinearClampSampler;
		}
	}
	else if( type == BINDING_LAYOUT_BLENDLIGHT )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() )
			};
		}
		else
		{
			auto& bindings = desc[1].bindings;
			bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
		}

		if( desc[2].bindings.empty() )
		{
			desc[2].bindings =
			{
				nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_LinearBorderSampler )
			};
		}
		else
		{
			desc[2].bindings[0].resourceHandle = commonPasses.m_LinearBorderSampler;
		}
	}
	else if( type == BINDING_LAYOUT_BLENDLIGHT_SKINNED )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::StructuredBuffer_SRV( 11, currentJointBuffer, nvrhi::Format::UNKNOWN, nvrhi::BufferRange( currentJointOffset, sizeof( idVec4 ) * numBoneMatrices ) )
			};
		}
		else
		{
			auto& bindings = desc[0].bindings;
			bindings[0].resourceHandle = paramCb;
			bindings[0].range = range;
			bindings[1].resourceHandle = currentJointBuffer;
			bindings[1].range = nvrhi::BufferRange{ currentJointOffset, sizeof( idVec4 )* numBoneMatrices };
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() )
			};
		}
		else
		{
			auto& bindings = desc[1].bindings;
			bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
		}

		if( desc[2].bindings.empty() )
		{
			desc[2].bindings =
			{
				nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_LinearBorderSampler )
			};
		}
		else
		{
			desc[2].bindings[0].resourceHandle = commonPasses.m_LinearBorderSampler;
		}
	}
	else if( type == BINDING_LAYOUT_POST_PROCESS_INGAME )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 2, ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID() )
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
			desc[0].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			desc[0].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
			desc[0].bindings[3].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID();
		}

		if( R_UsePixelatedLook() )
		{
			if( desc[1].bindings.empty() )
			{
				desc[1].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointClampSampler )
				};
			}
			else
			{
				desc[1].bindings[0].resourceHandle = commonPasses.m_PointClampSampler;
			}
		}
		else
		{
			if( desc[1].bindings.empty() )
			{
				desc[1].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_LinearClampSampler )
				};
			}
			else
			{
				desc[1].bindings[0].resourceHandle = commonPasses.m_LinearClampSampler;
			}
		}
	}
	else if( type == BINDING_LAYOUT_POST_PROCESS_FINAL )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() )
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
			desc[0].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			desc[0].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_LinearClampSampler ),
				nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearWrapSampler )
			};
		}
		else
		{
			desc[1].bindings[0].resourceHandle = commonPasses.m_LinearClampSampler;
			desc[1].bindings[1].resourceHandle = commonPasses.m_LinearWrapSampler;
		}
	}
	else if( type == BINDING_LAYOUT_POST_PROCESS_FINAL2 )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 2, ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 3, ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID() )
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
			desc[0].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			desc[0].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
			desc[0].bindings[3].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID();
			desc[0].bindings[4].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 3 )->GetTextureID();
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_LinearClampSampler ),
				nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearWrapSampler )
			};
		}
		else
		{
			desc[1].bindings[0].resourceHandle = commonPasses.m_LinearClampSampler;
			desc[1].bindings[1].resourceHandle = commonPasses.m_LinearWrapSampler;
		}
	}
	else if( type == BINDING_LAYOUT_POST_PROCESS_CRT )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() )
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
			desc[0].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			desc[0].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointClampSampler ),
				nvrhi::BindingSetItem::Sampler( 1, commonPasses.m_LinearWrapSampler )
			};
		}
		else
		{
			desc[1].bindings[0].resourceHandle = commonPasses.m_PointClampSampler;
			desc[1].bindings[1].resourceHandle = commonPasses.m_LinearWrapSampler;
		}
	}
	else if( type == BINDING_LAYOUT_NORMAL_CUBE )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() )
			};
		}
		else
		{
			auto& bindings = desc[1].bindings;
			bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
		}

		if( R_UsePixelatedLook() )
		{
			if( desc[2].bindings.empty() )
			{
				desc[2].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointWrapSampler )
				};
			}
			else
			{
				desc[2].bindings[0].resourceHandle = commonPasses.m_PointWrapSampler;
			}
		}
		else
		{
			if( desc[2].bindings.empty() )
			{
				desc[2].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_LinearWrapSampler )
				};
			}
			else
			{
				desc[2].bindings[0].resourceHandle = commonPasses.m_LinearWrapSampler;
			}
		}
	}
	else if( type == BINDING_LAYOUT_NORMAL_CUBE_SKINNED )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0,  paramCb, range ),
				nvrhi::BindingSetItem::StructuredBuffer_SRV( 11, currentJointBuffer, nvrhi::Format::UNKNOWN, nvrhi::BufferRange( currentJointOffset, sizeof( idVec4 ) * numBoneMatrices ) )
			};
		}
		else
		{
			auto& bindings = desc[0].bindings;
			bindings[0].resourceHandle = paramCb;
			bindings[0].range = range;

			bindings[1].resourceHandle = currentJointBuffer;
			bindings[1].range = nvrhi::BufferRange{ currentJointOffset, sizeof( idVec4 )* numBoneMatrices };
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() )
			};
		}
		else
		{
			auto& bindings = desc[1].bindings;
			bindings[0].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
		}

		if( R_UsePixelatedLook() )
		{
			if( desc[2].bindings.empty() )
			{
				desc[2].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointWrapSampler )
				};
			}
			else
			{
				desc[2].bindings[0].resourceHandle = commonPasses.m_PointWrapSampler;
			}
		}
		else
		{
			if( desc[2].bindings.empty() )
			{
				desc[2].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_LinearWrapSampler )
				};
			}
			else
			{
				desc[2].bindings[0].resourceHandle = commonPasses.m_LinearWrapSampler;
			}
		}
	}
	else if( type == BINDING_LAYOUT_BINK_VIDEO )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 2, ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID() )
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
			desc[0].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			desc[0].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
			desc[0].bindings[3].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 2 )->GetTextureID();
		}

		if( R_UsePixelatedLook() )
		{
			if( desc[1].bindings.empty() )
			{
				desc[1].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_PointWrapSampler )
				};
			}
			else
			{
				desc[1].bindings[0].resourceHandle = commonPasses.m_PointWrapSampler;
			}
		}
		else
		{
			if( desc[1].bindings.empty() )
			{
				desc[1].bindings =
				{
					nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_LinearWrapSampler )
				};
			}
			else
			{
				desc[1].bindings[0].resourceHandle = commonPasses.m_LinearWrapSampler;
			}
		}
	}
	else if( type == BINDING_LAYOUT_TAA_MOTION_VECTORS )
	{
		if( desc[0].bindings.empty() )
		{
			desc[0].bindings =
			{
				nvrhi::BindingSetItem::ConstantBuffer( 0, paramCb, range ),
				nvrhi::BindingSetItem::Texture_SRV( 0, ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID() ),
				nvrhi::BindingSetItem::Texture_SRV( 1, ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID() )
			};
		}
		else
		{
			desc[0].bindings[0].resourceHandle = paramCb;
			desc[0].bindings[0].range = range;
			desc[0].bindings[1].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 0 )->GetTextureID();
			desc[0].bindings[2].resourceHandle = ( nvrhi::ITexture* )GetImageAt( 1 )->GetTextureID();
		}

		if( desc[1].bindings.empty() )
		{
			desc[1].bindings =
			{
				nvrhi::BindingSetItem::Sampler( 0, commonPasses.m_LinearClampSampler )
			};
		}
		else
		{
			desc[1].bindings[0].resourceHandle = commonPasses.m_LinearClampSampler;
		}
	}
	else
	{
		common->FatalError( "Invalid binding set %d\n", renderProgManager.BindingLayoutType() );
	}
}

/*
=========================================================================================================

GL COMMANDS

=========================================================================================================
*/

/*
==================
idRenderBackend::GL_StartFrame
==================
*/
void idRenderBackend::GL_StartFrame()
{
	OPTICK_EVENT( "StartFrame" );

	// fetch GPU timer queries of last frame
	renderLog.FetchGPUTimers( pc );

	deviceManager->BeginFrame();

#if defined( USE_AMD_ALLOCATOR )
	idImage::EmptyGarbage();
#endif

	commandList->open();

	renderLog.StartFrame( commandList );
	renderLog.OpenMainBlock( MRB_GPU_TIME );
}

/*
==================
idRenderBackend::GL_EndFrame
==================
*/
void idRenderBackend::GL_EndFrame()
{
	uint32_t swapIndex = deviceManager->GetCurrentBackBufferIndex();

	OPTICK_EVENT( "EndFrame" );
	//OPTICK_TAG( "Firing to swapIndex", swapIndex );

	if( deviceManager->GetGraphicsAPI() == nvrhi::GraphicsAPI::VULKAN )
	{
		tr.SetReadyToPresent();
	}

	renderLog.CloseMainBlock( MRB_GPU_TIME );

	commandList->close();

	// required for Vulkan: transition our swap image to present
	deviceManager->EndFrame();

	// SRS - execute after EndFrame() to avoid need for barrier command list on Vulkan
	deviceManager->GetDevice()->executeCommandList( commandList );

	// update jitter for perspective matrix
	taaPass->AdvanceFrame();
}

/*
=============
GL_BlockingSwapBuffers

We want to exit this with the GPU idle, right at vsync
=============
*/
void idRenderBackend::GL_BlockingSwapBuffers()
{
	uint32_t swapIndex = deviceManager->GetCurrentBackBufferIndex();

	OPTICK_CATEGORY( "BlockingSwapBuffers", Optick::Category::Wait );
	//OPTICK_TAG( "Waiting for swapIndex", swapIndex );

	// SRS - device-level sync kills perf by serializing command queue processing (CPU) and rendering (GPU)
	//	   - instead, use alternative sync method (based on command queue event queries) inside Present()
	//deviceManager->GetDevice()->waitForIdle();

	// Make sure that all frames have finished rendering
	deviceManager->Present();

	// Release all in-flight references to the render targets
	deviceManager->GetDevice()->runGarbageCollection();

	renderLog.EndFrame();

	if( deviceManager->GetGraphicsAPI() == nvrhi::GraphicsAPI::VULKAN )
	{
		tr.InvalidateSwapBuffers();
	}
}

/*
========================
GL_SetDefaultState

This should initialize all GL state that any part of the entire program
may touch, including the editor.
========================
*/
void idRenderBackend::GL_SetDefaultState()
{
	renderLog.OpenBlock( "--- GL_SetDefaultState ---\n" );

	glStateBits = 0;

	GL_State( 0, true );

	GL_Scissor( 0, 0, renderSystem->GetWidth(), renderSystem->GetHeight() );

	renderProgManager.Unbind();

	Framebuffer::Unbind();

	renderLog.CloseBlock();
}

/*
====================
idRenderBackend::GL_State

This routine is responsible for setting the most commonly changed state
====================
*/
void idRenderBackend::GL_State( uint64 stateBits, bool forceGlState )
{
	glStateBits = stateBits | ( glStateBits & GLS_KEEP );
	if( viewDef != NULL && viewDef->isMirror )
	{
		glStateBits |= GLS_MIRROR_VIEW;
	}

	// the rest of this is handled by PipelineCache::GetOrCreatePipeline and GetRenderState similar to Vulkan
}

/*
====================
idRenderBackend::SelectTexture
====================
*/
void idRenderBackend::GL_SelectTexture( int unit )
{
	context.currentImageParm = unit;
}

/*
====================
idRenderBackend::GL_Scissor
====================
*/
void idRenderBackend::GL_Scissor( int x /* left*/, int y /* bottom */, int w, int h )
{
	context.scissor.Clear();
	context.scissor.AddPoint( x, y );
	context.scissor.AddPoint( x + w, y + h );
}

/*
====================
idRenderBackend::GL_Viewport
====================
*/
void idRenderBackend::GL_Viewport( int x /* left */, int y /* bottom */, int w, int h )
{
	currentViewport.Clear();
	currentViewport.AddPoint( x, y );
	currentViewport.AddPoint( x + w, y + h );
}

/*
====================
idRenderBackend::GL_PolygonOffset
====================
*/
void idRenderBackend::GL_PolygonOffset( float scale, float bias )
{
	slopeScaleBias = scale;
	depthBias = bias;
}

/*
========================
idRenderBackend::GL_DepthBoundsTest
========================
*/
void idRenderBackend::GL_DepthBoundsTest( const float zmin, const float zmax )
{
	if( /*!glConfig.depthBoundsTestAvailable || */zmin > zmax )
	{
		return;
	}

	if( zmin == 0.0f && zmax == 0.0f )
	{
		glStateBits = glStateBits & ~GLS_DEPTH_TEST_MASK;
	}
	else
	{
		glStateBits |= GLS_DEPTH_TEST_MASK;

		// RB: current viewport should be always [0..1] but we store here the values for depth bounds testing
		// NVRHI does not support depth bounds testing at this moment
		currentViewport.zmin = zmin;
		currentViewport.zmax = zmax;
	}
}

/*
====================
idRenderBackend::GL_Color
====================
*/
void idRenderBackend::GL_Color( float r, float g, float b, float a )
{
	float parm[4];
	parm[0] = idMath::ClampFloat( 0.0f, 1.0f, r );
	parm[1] = idMath::ClampFloat( 0.0f, 1.0f, g );
	parm[2] = idMath::ClampFloat( 0.0f, 1.0f, b );
	parm[3] = idMath::ClampFloat( 0.0f, 1.0f, a );
	renderProgManager.SetRenderParm( RENDERPARM_COLOR, parm );
}

/*
========================
idRenderBackend::GL_Clear
========================
*/
void idRenderBackend::GL_Clear( bool color, bool depth, bool stencil, byte stencilValue, float r, float g, float b, float a, bool clearHDR )
{
	nvrhi::IFramebuffer* framebuffer = Framebuffer::GetActiveFramebuffer()->GetApiObject();

	if( color )
	{
		nvrhi::utils::ClearColorAttachment( commandList, framebuffer, 0, nvrhi::Color( 0.f ) );
	}

	if( clearHDR )
	{
		nvrhi::utils::ClearColorAttachment( commandList, globalFramebuffers.hdrFBO->GetApiObject(), 0, nvrhi::Color( 0.f ) );
	}

	if( depth || stencil )
	{
		// make sure both depth and stencil are handled

		const nvrhi::FramebufferAttachment& attDepth = framebuffer->getDesc().depthAttachment;
		if( attDepth.texture )
		{
			commandList->clearDepthStencilTexture( attDepth.texture, nvrhi::AllSubresources, depth, 1.0f, stencil, stencilValue );
		}
	}
}


/*
=================
idRenderBackend::GL_GetCurrentState
=================
*/
uint64 idRenderBackend::GL_GetCurrentState() const
{
	return glStateBits;
}

/*
========================
idRenderBackend::GL_GetCurrentStateMinusStencil
========================
*/
uint64 idRenderBackend::GL_GetCurrentStateMinusStencil() const
{
	return GL_GetCurrentState() & ~( GLS_STENCIL_OP_BITS | GLS_STENCIL_FUNC_BITS | GLS_STENCIL_FUNC_REF_BITS | GLS_STENCIL_FUNC_MASK_BITS );
}


/*
=============
idRenderBackend::CheckCVars

See if some cvars that we watch have changed
=============
*/
void idRenderBackend::CheckCVars()
{
	// TODO remove, gamma stuff doesn't work and isn't used using the latest Nvidia drivers
	if( r_gamma.IsModified() || r_brightness.IsModified() )
	{
		r_gamma.ClearModified();
		r_brightness.ClearModified();
		R_SetColorMappings();
	}

	// SRS - support dynamic changes to vsync setting
	if( r_swapInterval.IsModified() )
	{
		r_swapInterval.ClearModified();
		deviceManager->SetVsyncEnabled( r_swapInterval.GetInteger() );
	}

	// retro rendering
	if( r_renderMode.IsModified() )
	{
		r_renderMode.ClearModified();

		// clear caches because PSX rendering will use nearest texture filtering instead of linear
		ClearCaches();
	}
}

/*
=============
idRenderBackend::ClearCaches

Clear cached pipeline data when framebuffers get updated or images are reloaded.
=============
*/
void idRenderBackend::ClearCaches()
{
	pipelineCache.Clear();
	bindingCache.Clear();
	samplerCache.Clear();

	if( hiZGenPass )
	{
		delete hiZGenPass;
		hiZGenPass = nullptr;
	}

	if( ssaoPass )
	{
		delete ssaoPass;
		ssaoPass = nullptr;
	}

	if( toneMapPass )
	{
		delete toneMapPass;
		toneMapPass = nullptr;
	}

	if( taaPass )
	{
		delete taaPass;
		taaPass = nullptr;
	}

	currentVertexBuffer = nullptr;
	currentIndexBuffer = nullptr;
	currentJointBuffer = nullptr;
	currentIndexOffset = -1;
	currentVertexOffset = -1;
	currentBindingLayout = nullptr;
	currentPipeline = nullptr;
}

/*
============================================================================

RENDER BACK END THREAD FUNCTIONS

============================================================================
*/

/*
=============
idRenderBackend::DrawFlickerBox
=============
*/
void idRenderBackend::DrawFlickerBox()
{
	if( !r_drawFlickerBox.GetBool() )
	{
		return;
	}
	//if( tr.frameCount & 1 )
	//{
	//	glClearColor( 1, 0, 0, 1 );
	//}
	//else
	//{
	//	glClearColor( 0, 1, 0, 1 );
	//}
	//glScissor( 0, 0, 256, 256 );
	//glClear( GL_COLOR_BUFFER_BIT );
}

/*
=============
idRenderBackend::SetBuffer
=============
*/
void idRenderBackend::SetBuffer( const void* data )
{
	// see which draw buffer we want to render the frame to

	const setBufferCommand_t* cmd = ( const setBufferCommand_t* )data;

	nvrhi::ObjectType commandObject = nvrhi::ObjectTypes::D3D12_GraphicsCommandList;
	if( deviceManager->GetGraphicsAPI() == nvrhi::GraphicsAPI::VULKAN )
	{
		commandObject = nvrhi::ObjectTypes::VK_CommandBuffer;
	}
	OPTICK_GPU_CONTEXT( ( void* ) commandList->getNativeObject( commandObject ) );
	OPTICK_GPU_EVENT( "SetBuffer" );

	renderLog.OpenMainBlock( MRB_BEGIN_DRAWING_VIEW );
	renderLog.OpenBlock( "Render_SetBuffer" );

	currentScissor.Clear();
	currentScissor.AddPoint( 0, 0 );
	currentScissor.AddPoint( tr.GetWidth(), tr.GetHeight() );

	// clear screen for debugging
	// automatically enable this with several other debug tools
	// that might leave unrendered portions of the screen
	if( r_clear.GetFloat() || idStr::Length( r_clear.GetString() ) != 1 || r_singleArea.GetBool() || r_showOverDraw.GetBool() )
	{
		OPTICK_GPU_EVENT( "Render_ClearBuffer" );

		float c[3];
		if( sscanf( r_clear.GetString(), "%f %f %f", &c[0], &c[1], &c[2] ) == 3 )
		{
			GL_Clear( true, false, false, 0, c[0], c[1], c[2], 1.0f, true );
		}
		else if( r_clear.GetInteger() == 2 )
		{
			GL_Clear( true, false, false, 0, 0.0f, 0.0f, 0.0f, 1.0f, true );
		}
		else if( r_showOverDraw.GetBool() )
		{
			GL_Clear( true, false, false, 0, 1.0f, 1.0f, 1.0f, 1.0f, true );
		}
		else
		{
			GL_Clear( true, false, false, 0, 0.4f, 0.0f, 0.25f, 1.0f, true );
		}
	}

	renderLog.CloseBlock();
	renderLog.CloseMainBlock();
}


/*
=============
idRenderBackend::idRenderBackend
=============
*/
idRenderBackend::idRenderBackend()
{
	hiZGenPass = nullptr;
	ssaoPass = nullptr;

	memset( &glConfig, 0, sizeof( glConfig ) );

	glConfig.uniformBufferOffsetAlignment = 256;
	glConfig.timerQueryAvailable = true;
}

/*
=============
idRenderBackend::~idRenderBackend
=============
*/
idRenderBackend::~idRenderBackend()
{

}

/*
====================
R_MakeStereoRenderImage
====================
*/
static void R_MakeStereoRenderImage( idImage* image )
{
	idImageOpts	opts;
	opts.width = renderSystem->GetWidth();
	opts.height = renderSystem->GetHeight();
	opts.numLevels = 1;
	opts.format = FMT_RGBA8;
	image->AllocImage( opts, TF_LINEAR, TR_CLAMP );
}

/*
====================
idRenderBackend::StereoRenderExecuteBackEndCommands

Renders the draw list twice, with slight modifications for left eye / right eye
====================
*/
void idRenderBackend::StereoRenderExecuteBackEndCommands( const emptyCommand_t* const allCmds )
{
}

void idRenderBackend::ImGui_RenderDrawLists( ImDrawData* draw_data )
{
	if( draw_data->CmdListsCount == 0 )
	{
		// Nothing to do.
		return;
	}

	tr.guiModel->EmitImGui( draw_data );
}

/*
====================
idRenderBackend::ResizeImages
====================
*/
void idRenderBackend::ResizeImages()
{
	glimpParms_t parms;

	parms.width = glConfig.nativeScreenWidth;
	parms.height = glConfig.nativeScreenHeight;
	parms.multiSamples = glConfig.multisamples;

	deviceManager->UpdateWindowSize( parms );
}

void idRenderBackend::SetCurrentImage( idImage* image )
{
	// load the image if necessary (FIXME: not SMP safe!)
	// RB: don't try again if last time failed
	if( !image->IsLoaded() && !image->IsDefaulted() )
	{
		// TODO(Stephen): Fix me.
		image->ActuallyLoadImage( true, commandList );
	}

	context.imageParms[context.currentImageParm] = image;
}

idImage* idRenderBackend::GetCurrentImage()
{
	return context.imageParms[context.currentImageParm];
}

idImage* idRenderBackend::GetImageAt( int index )
{
	return context.imageParms[index];
}

void idRenderBackend::ResetPipelineCache()
{
	pipelineCache.Clear();
}

extern "C" unsigned long c_commandListHandle_reset(nvrhi::CommandListHandle* ref) {
	return ref->Reset();
}

extern "C" void c_device_waitForIdle(nvrhi::IDevice* device) {
	device->waitForIdle();
}

extern "C" void c_device_executeCommandList(nvrhi::IDevice* device, nvrhi::ICommandList* commandList) {
	device->executeCommandList(commandList);
}

extern "C" nvrhi::ICommandList* c_device_createCommandList(nvrhi::IDevice* device) {
	nvrhi::CommandListHandle wrapper_handle = device->createCommandList();

	return wrapper_handle.Detach();
}

extern "C" void c_commandList_open(nvrhi::ICommandList* commandList) {
	commandList->open();
}

extern "C" void c_commandList_close(nvrhi::ICommandList* commandList) {
	commandList->close();
}

extern "C" void c_renderBackend_shutdown(idRenderBackend* instance) {
	instance->Shutdown();
}

extern "C" void c_renderBackend_init(idRenderBackend* instance) {
	instance->Init();
}

extern "C" void c_renderBackend_checkCVars(idRenderBackend* instance) {
	instance->CheckCVars();
}
