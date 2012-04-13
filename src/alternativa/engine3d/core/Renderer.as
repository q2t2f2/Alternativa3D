/**
 * This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/.
 * If it is not possible or desirable to put the notice in a particular file, then You may include the notice in a location (such as a LICENSE file in a relevant directory) where a recipient would be likely to look for such a notice.
 * You may add additional accurate notices of copyright ownership.
 *
 * It is desirable to notify that Covered Software was "Powered by AlternativaPlatform" with link to http://www.alternativaplatform.com/ 
 * */

package alternativa.engine3d.core {

	import alternativa.engine3d.alternativa3d;
	import alternativa.engine3d.materials.ShaderProgram;

	import flash.display3D.Context3D;
	import flash.display3D.Context3DCompareMode;
	import flash.display3D.Context3DProgramType;
	import flash.display3D.IndexBuffer3D;
	import flash.display3D.Program3D;
	import flash.utils.Dictionary;

	use namespace alternativa3d;

	/**
	 * @private 
	 */
	public class Renderer {

		public static const SKY:int = 10;

		public static const OPAQUE:int = 20;

		public static const OPAQUE_OVERHEAD:int = 25;

		public static const DECALS:int = 30;

		public static const TRANSPARENT_SORT:int = 40;

		public static const NEXT_LAYER:int = 50;

		// Collector
		protected var collector:DrawUnit;

		alternativa3d var camera:Camera3D;

		alternativa3d var drawUnits:Vector.<DrawUnit> = new Vector.<DrawUnit>();
		
		// Key - context, value - properties.
		protected static var properties:Dictionary = new Dictionary(true);

		protected var _context3D:Context3D;
		protected var _contextProperties:RendererContext3DProperties;

		alternativa3d function render(context3D:Context3D):void {
			updateContext3D(context3D);

			var drawUnitsLength:int = drawUnits.length;
			for (var i:int = 0; i < drawUnitsLength; i++) {
				var list:DrawUnit = drawUnits[i];
				if (list != null) {
					switch (i) {
						case SKY:
							_context3D.setDepthTest(false, Context3DCompareMode.ALWAYS);
							break;
						case OPAQUE:
							_context3D.setDepthTest(true, Context3DCompareMode.LESS);
							break;
						case OPAQUE_OVERHEAD:
							_context3D.setDepthTest(false, Context3DCompareMode.EQUAL);
							break;
						case DECALS:
							_context3D.setDepthTest(false, Context3DCompareMode.LESS_EQUAL);
							break;
						case TRANSPARENT_SORT:
							if (list.next != null) list = sortByAverageZ(list);
							_context3D.setDepthTest(false, Context3DCompareMode.LESS);
							break;
						case NEXT_LAYER:
							_context3D.setDepthTest(false, Context3DCompareMode.ALWAYS);
							break;
					}
					// Rendering
					while (list != null) {
						var next:DrawUnit = list.next;
						renderDrawUnit(list, _context3D, camera);
						// Send to collector
						list.clear();
						list.next = collector;
						collector = list;
						list = next;
					}
				}
			}
			// Clear
			drawUnits.length = 0;
		}

		alternativa3d function createDrawUnit(object:Object3D, program:Program3D, indexBuffer:IndexBuffer3D, firstIndex:int, numTriangles:int, debugShader:ShaderProgram = null):DrawUnit {
			var res:DrawUnit;
			if (collector != null) {
				res = collector;
				collector = collector.next;
				res.next = null;
			} else {
				//trace("new DrawUnit");
				res = new DrawUnit();
			}
			res.object = object;
			res.program = program;
			res.indexBuffer = indexBuffer;
			res.firstIndex = firstIndex;
			res.numTriangles = numTriangles;
			return res;
		}

		alternativa3d function addDrawUnit(drawUnit:DrawUnit, renderPriority:int):void {
			// Increase array of priorities, if it is necessary
			if (renderPriority >= drawUnits.length) drawUnits.length = renderPriority + 1;
			// Add
			drawUnit.next = drawUnits[renderPriority];
			drawUnits[renderPriority] = drawUnit;
		}

		protected function renderDrawUnit(drawUnit:DrawUnit, context:Context3D, camera:Camera3D):void {
			context.setBlendFactors(drawUnit.blendSource, drawUnit.blendDestination);
			context.setCulling(drawUnit.culling);
			var _usedBuffers:uint = _contextProperties.usedBuffers;
			var _usedTextures:uint = _contextProperties.usedTextures;

			var bufferIndex:int;
			var bufferBit:int;
			var currentBuffers:int;
			var textureSampler:int;
			var textureBit:int;
			var currentTextures:int;
			for (var i:int = 0; i < drawUnit.vertexBuffersLength; i++) {
				bufferIndex = drawUnit.vertexBuffersIndexes[i];
				bufferBit = 1 << bufferIndex;
				currentBuffers |= bufferBit;
				_usedBuffers &= ~bufferBit;
				context.setVertexBufferAt(bufferIndex, drawUnit.vertexBuffers[i], drawUnit.vertexBuffersOffsets[i], drawUnit.vertexBuffersFormats[i]);
			}
			if (drawUnit.vertexConstantsRegistersCount > 0) {
				context.setProgramConstantsFromVector(Context3DProgramType.VERTEX, 0, drawUnit.vertexConstants, drawUnit.vertexConstantsRegistersCount);
			}
			if (drawUnit.fragmentConstantsRegistersCount > 0) {
				context.setProgramConstantsFromVector(Context3DProgramType.FRAGMENT, 0, drawUnit.fragmentConstants, drawUnit.fragmentConstantsRegistersCount);
			}
			for (i = 0; i < drawUnit.texturesLength; i++) {
				textureSampler = drawUnit.texturesSamplers[i];
				textureBit = 1 << textureSampler;
				currentTextures |= textureBit;
				_usedTextures &= ~textureBit;
				context.setTextureAt(textureSampler, drawUnit.textures[i]);
			}
			context.setProgram(drawUnit.program);
			for (bufferIndex = 0; _usedBuffers > 0; bufferIndex++) {
				bufferBit = _usedBuffers & 1;
				_usedBuffers >>= 1;
				if (bufferBit) context.setVertexBufferAt(bufferIndex, null);
			}
			for (textureSampler = 0; _usedTextures > 0; textureSampler++) {
				textureBit = _usedTextures & 1;
				_usedTextures >>= 1;
				if (textureBit) context.setTextureAt(textureSampler, null);
			}
			context.drawTriangles(drawUnit.indexBuffer, drawUnit.firstIndex, drawUnit.numTriangles);
			_contextProperties.usedBuffers = currentBuffers;
			_contextProperties.usedTextures = currentTextures;
			camera.numDraws++;
			camera.numTriangles += drawUnit.numTriangles;
		}

		protected function updateContext3D(value:Context3D):void {
			if (_context3D != value) {
				_contextProperties = properties[value];
				if (_contextProperties == null) {
					_contextProperties = new RendererContext3DProperties();
					properties[value] = _contextProperties;
				}
				_context3D = value;
			}
		}

		alternativa3d function sortByAverageZ(list:DrawUnit, direction:Boolean = true):DrawUnit {
			var left:DrawUnit = list;
			var right:DrawUnit = list.next;
			while (right != null && right.next != null) {
				list = list.next;
				right = right.next.next;
			}
			right = list.next;
			list.next = null;
			if (left.next != null) {
				left = sortByAverageZ(left, direction);
			}
			if (right.next != null) {
				right = sortByAverageZ(right, direction);
			}
			var flag:Boolean = direction ? (left.object.localToCameraTransform.l > right.object.localToCameraTransform.l) : (left.object.localToCameraTransform.l < right.object.localToCameraTransform.l);
			if (flag) {
				list = left;
				left = left.next;
			} else {
				list = right;
				right = right.next;
			}
			var last:DrawUnit = list;
			while (true) {
				if (left == null) {
					last.next = right;
					return list;
				} else if (right == null) {
					last.next = left;
					return list;
				}
				if (flag) {
					if (direction ? (left.object.localToCameraTransform.l > right.object.localToCameraTransform.l) : (left.object.localToCameraTransform.l < right.object.localToCameraTransform.l)) {
						last = left;
						left = left.next;
					} else {
						last.next = right;
						last = right;
						right = right.next;
						flag = false;
					}
				} else {
					if (direction ? (left.object.localToCameraTransform.l < right.object.localToCameraTransform.l) : (left.object.localToCameraTransform.l > right.object.localToCameraTransform.l)) {
						last = right;
						right = right.next;
					} else {
						last.next = left;
						last = left;
						left = left.next;
						flag = true;
					}
				}
			}
			return null;
		}
	}
}
